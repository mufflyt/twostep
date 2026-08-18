#' Build empirically calibrated multi-location E2SFCA capacity weights 
#' 
#' Uses CHIA claim-line location information to estimate clinician-specific 
#' location shares, learns a transportable allocation model, applies the model 
#' to national primary/secondary practice locations, and preserves total 
#' clinician capacity exactly across all locations. 
#' 
#' @param chia_claims_path Path to CHIA medical claims, CSV-like or Parquet. 
#' @param chia_provider_path Path to CHIA provider file, CSV-like or Parquet. 
#' @param national_locations_path Path to national clinician-location file. 
#' @param target_npis Character vector of NPIs to include. 
#' @param save_dir Directory for timestamped analytic artifacts. 
#' @param claim_map Named list mapping CHIA claim fields. 
#' @param provider_map Named list mapping CHIA provider fields. 
#' @param location_map Named list mapping national location fields. 
#' @param capacity_path Optional CSV with one capacity value per NPI. 
#' @param capacity_map Named list with npi and capacity field names. 
#' @param wrvu_path Optional CSV containing HCPCS-to-work-RVU values. 
#' @param wrvu_map Named list with hcpcs and wrvu field names. 
#' @param medicare_path Optional CSV/Parquet for NPI-level Medicare validation. 
#' @param medicare_map Named list mapping Medicare validation fields. 
#' @param cadr_path Optional CSV/Parquet for CADR location validation. 
#' @param cadr_map Named list mapping CADR fields. 
#' @param claims_delim Delimiter for non-Parquet CHIA claims. 
#' @param provider_delim Delimiter for non-Parquet CHIA provider file. 
#' @param locations_delim Delimiter for non-Parquet national locations. 
#' @param medicare_delim Delimiter for non-Parquet Medicare file. 
#' @param cadr_delim Delimiter for non-Parquet CADR file. 
#' @param study_start Optional inclusive service date. 
#' @param study_end Optional inclusive service date. 
#' @param min_chia_days Minimum observed clinician-days for model training. 
#' @param min_match_coverage Minimum CHIA weight mapped to canonical locations. 
#' @param cv_folds Number of clinician-level cross-validation folds. 
#' @param min_training_npis Minimum multi-location NPIs required to model. 
#' @param seed Random seed for clinician-level cross-validation. 
#' 
#' @return Invisibly returns a named list of analytic tables and the fitted 
#' allocation model. Timestamped CSV files are also written to save_dir. 
build_multisite_e2sfca_weights <- function( 
  chia_claims_path, 
  chia_provider_path, 
  national_locations_path, 
  target_npis, 
  save_dir, 
  claim_map = list( 
    payer_id = "MC001", 
    rendering_provider_id = "MC134", 
    provider_location_id = "MC135", 
    service_date = "MC059", 
    hcpcs = "MC055", 
    denied_flag = "MC123" 
  ), 
  provider_map = list( 
    payer_id = "PV001", 
    provider_id = "PV002", 
    npi = "PV039", 
    address1 = "PV016", 
    address2 = "PV017", 
    city = "PV018", 
    state = "PV019", 
    zip = "PV021" 
  ), 
  location_map = list( 
    npi = "npi", 
    address1 = "address1", 
    address2 = "address2", 
    city = "city", 
    state = "state", 
    zip = "zip", 
    is_primary = "is_primary", 
    lat = "lat", 
    lon = "lon", 
    rural = "rural" 
  ), 
  capacity_path = NULL, 
  capacity_map = list( npi = "npi", capacity = "capacity_fte" ), 
  wrvu_path = NULL, 
  wrvu_map = list( hcpcs = "hcpcs", wrvu = "work_rvu" ), 
  medicare_path = NULL, 
  medicare_map = list( npi = "npi", services = "total_services", beneficiary_days = "beneficiary_day_services" ), 
  cadr_path = NULL, 
  cadr_map = list( npi = "npi", address1 = "address1", address2 = "address2", city = "city", state = "state", zip = "zip", service_date = "service_date" ), 
  claims_delim = ",", 
  provider_delim = ",", 
  locations_delim = ",", 
  medicare_delim = ",", 
  cadr_delim = ",", 
  study_start = NULL, 
  study_end = NULL, 
  min_chia_days = 10, 
  min_match_coverage = 0.95, 
  cv_folds = 5L, 
  min_training_npis = 20L, 
  seed = 20260813L) { 
  
  log_step <- function(...) { 
    base::message( base::paste0( "[", base::format(base::Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", base::paste0(..., collapse = "") ) ) 
  } 
  
  read_large <- function(path, delim = ",") { 
    extension <- base::tolower(tools::file_ext(path)) 
    if (!base::file.exists(path)) { base::stop("File does not exist: ", path) } 
    if (base::identical(extension, "parquet")) { 
      return( duckplyr::read_parquet_duckdb( path, prudence = "thrifty" ) ) 
    } 
    duckplyr::read_csv_duckdb( path, prudence = "thrifty", options = list( delim = delim, header = TRUE ) ) 
  } 
  
  read_small <- function(path, delim = ",") { 
    extension <- base::tolower(tools::file_ext(path)) 
    if (!base::file.exists(path)) { base::stop("File does not exist: ", path) } 
    if (base::identical(extension, "parquet")) { 
      return( arrow::read_parquet(path) |> tibble::as_tibble() ) 
    } 
    readr::read_delim( file = path, delim = delim, show_col_types = FALSE, progress = FALSE ) 
  } 
  
  normalize_zip <- function(x) { 
    x |> base::as.character() |> stringr::str_replace_all("[^0-9]", "") |> stringr::str_sub(1L, 5L) |> dplyr::na_if("") 
  } 
  
  normalize_text <- function(x) { 
    x |> base::as.character() |> tidyr::replace_na("") |> stringr::str_to_upper() |> stringr::str_replace_all("&", " AND ") |> stringr::str_replace_all("[^A-Z0-9]", "") |> stringr::str_squish() 
  } 
  
  make_address_key <- function( address1, address2, city, state, zip) { 
    base::paste( normalize_text(address1), normalize_text(address2), normalize_text(city), normalize_text(state), normalize_zip(zip), sep = "|" ) 
  } 
  
  parse_bool <- function(x) { 
    normalized <- x |> base::as.character() |> stringr::str_to_lower() |> stringr::str_trim() 
    normalized %in% base::c( "1", "true", "t", "yes", "y", "primary", "rural" ) 
  } 
  
  first_nonmissing <- function(x) { 
    kept <- x[!base::is.na(x)] 
    if (base::length(kept) == 0L) { return(NA) } 
    kept[[1L]] 
  } 
  
  haversine_km <- function(lat1, lon1, lat2, lon2) { 
    earth_km <- 6371.0088 
    rad <- base::pi / 180 
    lat1r <- lat1 * rad 
    lon1r <- lon1 * rad 
    lat2r <- lat2 * rad 
    lon2r <- lon2 * rad 
    dlat <- lat2r - lat1r 
    dlon <- lon2r - lon1r 
    hav <- base::sin(dlat / 2)^2 + base::cos(lat1r) * base::cos(lat2r) * base::sin(dlon / 2)^2 
    2 * earth_km * base::asin( base::pmin(1, base::sqrt(hav)) ) 
  } 
  
  fit_share_model <- function(training_rows, formula_object) { 
    stats::glm( formula = formula_object, family = stats::quasibinomial(), weights = observed_days, data = training_rows ) 
  } 
  
  normalize_prediction <- function(prediction_rows, score_col) { 
    prediction_rows |> dplyr::group_by(.data$npi) |> dplyr::mutate( .score_sum = base::sum( .data[[score_col]], na.rm = TRUE ), predicted_weight = dplyr::if_else( .data$.score_sum > 0, .data[[score_col]] / .data$.score_sum, 1 / dplyr::n() ) ) |> dplyr::ungroup() |> dplyr::select(-.data$.score_sum) 
  } 
  
  save_csv <- function(table_rows, stem, stamp) { 
    path <- base::file.path( save_dir, base::paste0(stem, "_", stamp, ".csv") ) 
    readr::write_csv( table_rows, file = path, na = "" ) 
    log_step("Saved: ", path) 
    path 
  } 
  
  stamp <- base::format( base::Sys.time(), "%Y%m%d_%H%M%S" ) 
  base::dir.create( save_dir, recursive = TRUE, showWarnings = FALSE ) 
  
  target_npis <- target_npis |> base::as.character() |> base::unique() 
  target_npis <- target_npis[ !base::is.na(target_npis) & base::nzchar(target_npis) ] 
  if (base::length(target_npis) == 0L) { base::stop("target_npis is empty.") } 
  
  log_step( "Inputs: ", base::format( base::length(target_npis), big.mark = "," ), " target NPIs." ) 
  log_step("CHIA claims: ", chia_claims_path) 
  log_step("CHIA provider file: ", chia_provider_path) 
  log_step("National locations: ", national_locations_path) 
  
  location_raw <- read_large( national_locations_path, locations_delim ) 
  if (base::is.null(location_map$address2)) { 
    location_raw <- location_raw |> dplyr::mutate(.address2 = NA_character_) 
    location_address2_col <- ".address2" 
  } else { 
    location_address2_col <- location_map$address2 
  } 
  if (base::is.null(location_map$rural)) { 
    location_raw <- location_raw |> dplyr::mutate(.rural = NA_character_) 
    location_rural_col <- ".rural" 
  } else { 
    location_rural_col <- location_map$rural 
  } 
  
  log_step("Filtering national locations to target NPIs.") 
  canonical_locations <- location_raw |> dplyr::transmute( 
    npi = base::as.character( .data[[location_map$npi]] ), 
    address1 = base::as.character( .data[[location_map$address1]] ), 
    address2 = base::as.character( .data[[location_address2_col]] ), 
    city = base::as.character( .data[[location_map$city]] ), 
    state = base::as.character( .data[[location_map$state]] ), 
    zip = base::as.character( .data[[location_map$zip]] ), 
    is_primary_raw = .data[[location_map$is_primary]], 
    lat = base::as.numeric( .data[[location_map$lat]] ), 
    lon = base::as.numeric( .data[[location_map$lon]] ), 
    rural_raw = .data[[location_rural_col]] 
  ) |> dplyr::filter(.data$npi %in% target_npis) |> dplyr::collect() |> dplyr::mutate( 
    zip5 = normalize_zip(.data$zip), 
    address_key = make_address_key( .data$address1, .data$address2, .data$city, .data$state, .data$zip ), 
    is_primary = parse_bool(.data$is_primary_raw), 
    rural = parse_bool(.data$rural_raw) 
  ) |> dplyr::group_by( .data$npi, .data$address_key ) |> dplyr::summarise( 
    address1 = first_nonmissing(.data$address1), 
    address2 = first_nonmissing(.data$address2), 
    city = first_nonmissing(.data$city), 
    state = first_nonmissing(.data$state), 
    zip5 = first_nonmissing(.data$zip5), 
    lat = first_nonmissing(.data$lat), 
    lon = first_nonmissing(.data$lon), 
    is_primary = base::any( .data$is_primary, na.rm = TRUE ), 
    rural = base::any( .data$rural, na.rm = TRUE ), 
    .groups = "drop" 
  ) |> dplyr::mutate( 
    canonical_location_id = base::paste( .data$npi, .data$address_key, sep = "::" ) 
  ) 
  
  log_step( "Canonical location rows after address deduplication: ", base::format( base::nrow(canonical_locations), big.mark = "," ) ) 
  
  primary_guard <- canonical_locations |> dplyr::group_by(.data$npi) |> dplyr::summarise( n_primary = base::sum( .data$is_primary, na.rm = TRUE ), n_locations = dplyr::n(), .groups = "drop" ) 
  bad_primary <- primary_guard |> dplyr::filter(.data$n_primary != 1L) 
  if (base::nrow(bad_primary) > 0L) { 
    bad_path <- save_csv( bad_primary, "multisite_bad_primary_flags", stamp ) 
    base::stop( "Each NPI must have exactly one primary location. See: ", bad_path ) 
  } 
  
  missing_geocode <- canonical_locations |> dplyr::filter( base::is.na(.data$lat) | base::is.na(.data$lon) ) 
  if (base::nrow(missing_geocode) > 0L) { 
    geocode_path <- save_csv( missing_geocode, "multisite_missing_geocodes", stamp ) 
    base::stop( "All E2SFCA locations need lat/lon. Missing rows saved to: ", geocode_path ) 
  } 
  
  primary_coordinates <- canonical_locations |> dplyr::filter(.data$is_primary) |> dplyr::select( .data$npi, primary_lat = .data$lat, primary_lon = .data$lon ) 
  canonical_locations <- canonical_locations |> dplyr::left_join( primary_coordinates, by = "npi" ) |> dplyr::mutate( 
    distance_km = haversine_km( .data$primary_lat, .data$primary_lon, .data$lat, .data$lon ) 
  ) |> dplyr::group_by(.data$npi) |> dplyr::mutate( 
    n_locations = dplyr::n(), 
    log_locations = base::log(.data$n_locations), 
    distance_100km = .data$distance_km / 100 
  ) |> dplyr::ungroup() 
  
  log_step("Reading CHIA provider linkage file with duckplyr.") 
  provider_raw <- read_large( chia_provider_path, provider_delim ) 
  if (base::is.null(provider_map$address2)) { 
    provider_raw <- provider_raw |> dplyr::mutate(.address2 = NA_character_) 
    provider_address2_col <- ".address2" 
  } else { 
    provider_address2_col <- provider_map$address2 
  } 
  provider_core <- provider_raw |> dplyr::transmute( 
    payer_id = base::as.character( .data[[provider_map$payer_id]] ), 
    provider_id = base::as.character( .data[[provider_map$provider_id]] ), 
    npi = base::as.character( .data[[provider_map$npi]] ), 
    address1 = base::as.character( .data[[provider_map$address1]] ), 
    address2 = base::as.character( .data[[provider_address2_col]] ), 
    city = base::as.character( .data[[provider_map$city]] ), 
    state = base::as.character( .data[[provider_map$state]] ), 
    zip = base::as.character( .data[[provider_map$zip]] ) 
  ) 
  
  rendering_lookup <- provider_core |> dplyr::filter( !base::is.na(.data$npi), .data$npi != "" ) |> dplyr::group_by( .data$payer_id, .data$provider_id ) |> dplyr::summarise( n_npi = dplyr::n_distinct(.data$npi), npi = base::min(.data$npi), .groups = "drop" ) |> dplyr::filter(.data$n_npi == 1L) |> dplyr::select( .data$payer_id, .data$provider_id, .data$npi ) 
  
  log_step("Reading CHIA medical claims with duckplyr.") 
  claim_raw <- read_large( chia_claims_path, claims_delim ) 
  if (base::is.null(claim_map$hcpcs)) { 
    claim_raw <- claim_raw |> dplyr::mutate(.hcpcs = NA_character_) 
    claim_hcpcs_col <- ".hcpcs" 
  } else { 
    claim_hcpcs_col <- claim_map$hcpcs 
  } 
  if (base::is.null(claim_map$denied_flag)) { 
    claim_raw <- claim_raw |> dplyr::mutate(.denied_flag = NA_character_) 
    claim_denied_col <- ".denied_flag" 
  } else { 
    claim_denied_col <- claim_map$denied_flag 
  } 
  
  relevant_claims <- claim_raw |> dplyr::transmute( 
    payer_id = base::as.character( .data[[claim_map$payer_id]] ), 
    rendering_provider_id = base::as.character( .data[[claim_map$rendering_provider_id]] ), 
    provider_location_id = base::as.character( .data[[claim_map$provider_location_id]] ), 
    service_date_raw = base::as.character( .data[[claim_map$service_date]] ), 
    hcpcs = base::as.character( .data[[claim_hcpcs_col]] ), 
    denied_flag = base::as.character( .data[[claim_denied_col]] ) 
  ) |> dplyr::left_join( 
    rendering_lookup, by = base::c( "payer_id", "rendering_provider_id" = "provider_id" ) 
  ) |> dplyr::filter(.data$npi %in% target_npis) 
  
  if (!base::is.null(claim_map$denied_flag)) { 
    relevant_claims <- relevant_claims |> dplyr::filter( base::is.na(.data$denied_flag) | .data$denied_flag != "1" ) 
  } 
  
  log_step( "Collecting CHIA claim lines only after NPI filtering." ) 
  claim_lines <- relevant_claims |> dplyr::collect() |> dplyr::mutate( service_date = lubridate::ymd( .data$service_date_raw, quiet = TRUE ) ) |> dplyr::filter( !base::is.na(.data$service_date), !base::is.na(.data$provider_location_id), .data$provider_location_id != "" ) 
  
  if (!base::is.null(study_start)) { 
    start_date <- base::as.Date(study_start) 
    claim_lines <- claim_lines |> dplyr::filter(.data$service_date >= start_date) 
  } 
  if (!base::is.null(study_end)) { 
    end_date <- base::as.Date(study_end) 
    claim_lines <- claim_lines |> dplyr::filter(.data$service_date <= end_date) 
  } 
  
  log_step( "Relevant CHIA claim lines: ", base::format( base::nrow(claim_lines), big.mark = "," ) ) 
  if (base::nrow(claim_lines) == 0L) { base::stop("No CHIA claim lines remained after filtering.") } 
  
  used_location_ids <- claim_lines |> dplyr::distinct( .data$payer_id, location_id = .data$provider_location_id ) 
  log_step( "Unique payer-location IDs used by target clinicians: ", base::format( base::nrow(used_location_ids), big.mark = "," ) ) 
  
  used_location_duck <- duckplyr::as_duckdb_tibble( used_location_ids ) 
  chia_location_lookup <- provider_core |> dplyr::inner_join( used_location_duck, by = base::c( "payer_id", "provider_id" = "location_id" ) ) |> dplyr::select( .data$payer_id, location_id = .data$provider_id, .data$address1, .data$address2, .data$city, .data$state, .data$zip ) |> dplyr::distinct() |> dplyr::collect() |> dplyr::mutate( zip5 = normalize_zip(.data$zip), address_key = make_address_key( .data$address1, .data$address2, .data$city, .data$state, .data$zip ) ) 
  
  location_ambiguity <- chia_location_lookup |> dplyr::group_by( .data$payer_id, .data$location_id ) |> dplyr::summarise( n_addresses = dplyr::n_distinct(.data$address_key), .groups = "drop" ) |> dplyr::filter(.data$n_addresses > 1L) 
  if (base::nrow(location_ambiguity) > 0L) { 
    ambiguity_path <- save_csv( location_ambiguity, "chia_ambiguous_location_ids", stamp ) 
    log_step( "Excluding ambiguous CHIA location IDs. Details: ", ambiguity_path ) 
  } 
  
  chia_location_lookup <- chia_location_lookup |> dplyr::anti_join( location_ambiguity |> dplyr::select( .data$payer_id, .data$location_id ), by = base::c( "payer_id", "location_id" ) ) |> dplyr::group_by( .data$payer_id, .data$location_id ) |> dplyr::slice(1L) |> dplyr::ungroup() 
  
  claim_lines <- claim_lines |> dplyr::left_join( chia_location_lookup |> dplyr::select( .data$payer_id, .data$location_id, .data$address_key, .data$zip5 ), by = base::c( "payer_id", "provider_location_id" = "location_id" ) ) |> dplyr::filter(!base::is.na(.data$address_key)) 
  
  if (!base::is.null(wrvu_path)) { 
    log_step("Joining HCPCS work RVUs: ", wrvu_path) 
    wrvu_crosswalk <- read_small(wrvu_path) |> dplyr::transmute( hcpcs = base::as.character( .data[[wrvu_map$hcpcs]] ), work_rvu = base::as.numeric( .data[[wrvu_map$wrvu]] ) ) |> dplyr::filter( !base::is.na(.data$hcpcs), !base::is.na(.data$work_rvu) ) |> dplyr::group_by(.data$hcpcs) |> dplyr::summarise( work_rvu = base::max( .data$work_rvu, na.rm = TRUE ), .groups = "drop" ) 
    claim_lines <- claim_lines |> dplyr::left_join( wrvu_crosswalk, by = "hcpcs" ) 
  } else { 
    log_step( "No wRVU crosswalk supplied; split days use claim-line shares." ) 
    claim_lines <- claim_lines |> dplyr::mutate(work_rvu = NA_real_) 
  } 
  
  wrvu_coverage <- claim_lines |> dplyr::summarise( n_lines = dplyr::n(), n_wrvu = base::sum( !base::is.na(.data$work_rvu) & .data$work_rvu > 0 ), wrvu_line_coverage = .data$n_wrvu / .data$n_lines ) 
  log_step( "wRVU line coverage: ", base::sprintf( "%.1f%%", 100 * wrvu_coverage$wrvu_line_coverage[[1L]] ) ) 
  
  log_step( "Constructing physician-location-days. One clinician-day sums to 1." ) 
  location_day_intensity <- claim_lines |> dplyr::group_by( .data$npi, .data$service_date, .data$address_key, .data$zip5 ) |> dplyr::summarise( claim_lines = dplyr::n(), work_rvu = base::sum( .data$work_rvu, na.rm = TRUE ), .groups = "drop" ) |> dplyr::group_by( .data$npi, .data$service_date ) |> dplyr::mutate( n_sites_that_day = dplyr::n(), day_total_wrvu = base::sum( .data$work_rvu, na.rm = TRUE ), day_total_lines = base::sum( .data$claim_lines, na.rm = TRUE ), day_fraction = dplyr::case_when( .data$n_sites_that_day == 1L ~ 1, .data$day_total_wrvu > 0 ~ .data$work_rvu / .data$day_total_wrvu, TRUE ~ .data$claim_lines / .data$day_total_lines ) ) |> dplyr::ungroup() 
  
  day_guard <- location_day_intensity |> dplyr::group_by( .data$npi, .data$service_date ) |> dplyr::summarise( day_sum = base::sum(.data$day_fraction), .groups = "drop" ) |> dplyr::summarise( max_day_error = base::max( base::abs(.data$day_sum - 1) ) ) 
  if (day_guard$max_day_error[[1L]] > 1e-10) { base::stop( "Physician-day fractions do not sum to 1. Maximum error: ", day_guard$max_day_error[[1L]] ) } 
  
  chia_observed_sites <- location_day_intensity |> dplyr::group_by( .data$npi, .data$address_key, .data$zip5 ) |> dplyr::summarise( day_equiv = base::sum(.data$day_fraction), observed_dates = dplyr::n_distinct(.data$service_date), .groups = "drop" ) |> dplyr::group_by(.data$npi) |> dplyr::mutate( observed_days = base::sum(.data$day_equiv), empirical_weight = .data$day_equiv / .data$observed_days ) |> dplyr::ungroup() 
  
  exact_matches <- chia_observed_sites |> dplyr::inner_join( canonical_locations |> dplyr::select( .data$npi, .data$address_key, .data$canonical_location_id ), by = base::c( "npi", "address_key" ) ) |> dplyr::mutate(match_method = "exact_address") 
  unmatched_sites <- chia_observed_sites |> dplyr::anti_join( exact_matches |> dplyr::select( .data$npi, .data$address_key ), by = base::c( "npi", "address_key" ) ) 
  
  unique_zip_sites <- canonical_locations |> dplyr::filter(!base::is.na(.data$zip5)) |> dplyr::group_by( .data$npi, .data$zip5 ) |> dplyr::filter(dplyr::n() == 1L) |> dplyr::ungroup() |> dplyr::select( .data$npi, .data$zip5, .data$canonical_location_id ) 
  zip_matches <- unmatched_sites |> dplyr::filter(!base::is.na(.data$zip5)) |> dplyr::inner_join( unique_zip_sites, by = base::c( "npi", "zip5" ) ) |> dplyr::mutate(match_method = "unique_npi_zip") 
  
  matched_sites <- dplyr::bind_rows( exact_matches, zip_matches ) |> dplyr::group_by( .data$npi, .data$canonical_location_id ) |> dplyr::summarise( day_equiv = base::sum(.data$day_equiv), observed_days = base::max(.data$observed_days), matched_weight = base::sum(.data$empirical_weight), match_method = base::paste( base::sort( base::unique(.data$match_method) ), collapse = "+" ), .groups = "drop" ) 
  
  match_coverage <- matched_sites |> dplyr::group_by(.data$npi) |> dplyr::summarise( matched_weight = base::sum(.data$matched_weight), observed_days = base::max(.data$observed_days), .groups = "drop" ) 
  unresolved_sites <- chia_observed_sites |> dplyr::anti_join( dplyr::bind_rows( exact_matches |> dplyr::select( .data$npi, .data$address_key ), zip_matches |> dplyr::select( .data$npi, .data$address_key ) ) |> dplyr::distinct(), by = base::c( "npi", "address_key" ) ) 
  
  log_step( "CHIA observed site rows unmatched to canonical locations: ", base::format( base::nrow(unresolved_sites), big.mark = "," ) ) 
  
  eligible_training_npis <- match_coverage |> dplyr::filter( .data$matched_weight >= min_match_coverage, .data$observed_days >= min_chia_days ) |> dplyr::pull(.data$npi) 
  training_rows <- canonical_locations |> dplyr::filter( .data$npi %in% eligible_training_npis, .data$n_locations >= 2L ) |> dplyr::left_join( matched_sites |> dplyr::select( .data$npi, .data$canonical_location_id, .data$day_equiv, .data$observed_days ), by = base::c( "npi", "canonical_location_id" ) ) |> dplyr::group_by(.data$npi) |> mutate( day_equiv = tidyr::replace_na(.data$day_equiv, 0), observed_days = base::max( .data$observed_days, na.rm = TRUE ), empirical_weight = .data$day_equiv / base::sum(.data$day_equiv) ) |> dplyr::ungroup() 
  
  n_training_npis <- training_rows |> dplyr::summarise( n = dplyr::n_distinct(.data$npi) ) |> dplyr::pull(.data$n) 
  log_step( "Multi-location NPIs eligible for CHIA calibration: ", base::format( n_training_npis, big.mark = "," ) ) 
  if (n_training_npis < min_training_npis) { 
    training_path <- save_csv( training_rows, "multisite_training_rows_insufficient", stamp ) 
    base::stop( "Only ", n_training_npis, " multi-location NPIs met training criteria; need at least ", min_training_npis, ". Inspect: ", training_path ) 
  } 
  
  predictor_names <- base::c( "is_primary", "log_locations" ) 
  if ( base::all( base::is.finite(training_rows$distance_100km) ) && stats::sd(training_rows$distance_100km) > 0 ) { 
    predictor_names <- base::c( predictor_names, "distance_100km" ) 
  } 
  if ( base::any(training_rows$rural) && base::any(!training_rows$rural) ) { 
    predictor_names <- base::c( predictor_names, "rural" ) 
  } 
  
  share_formula <- stats::reformulate( termlabels = predictor_names, response = "empirical_weight" ) 
  log_step( "Allocation model: ", base::paste( base::deparse(share_formula), collapse = " " ) ) 
  
  base::set.seed(seed) 
  clinician_folds <- training_rows |> dplyr::distinct(.data$npi) |> dplyr::mutate( fold = base::sample( base::rep( base::seq_len(cv_folds), length.out = dplyr::n() ) ) ) 
  
  cv_rows <- purrr::map_dfr( base::seq_len(cv_folds), function(fold_id) { 
    train_npis <- clinician_folds |> dplyr::filter(.data$fold != fold_id) |> dplyr::pull(.data$npi) 
    test_npis <- clinician_folds |> dplyr::filter(.data$fold == fold_id) |> dplyr::pull(.data$npi) 
    fold_train <- training_rows |> dplyr::filter(.data$npi %in% train_npis) 
    fold_test <- training_rows |> dplyr::filter(.data$npi %in% test_npis) 
    fold_model <- fit_share_model( fold_train, share_formula ) 
    fold_test |> dplyr::mutate( raw_score = base::pmin( 1 - 1e-6, base::pmax( 1e-6, stats::predict( fold_model, newdata = fold_test, type = "response" ) ) ), fold = fold_id ) |> normalize_prediction("raw_score") 
  } ) 
  
  cv_metrics <- cv_rows |> dplyr::summarise( n_npis = dplyr::n_distinct(.data$npi), mean_abs_error = base::mean( base::abs( .data$empirical_weight - .data$predicted_weight ) ), median_abs_error = stats::median( base::abs( .data$empirical_weight - .data$predicted_weight ) ), p25_abs_error = stats::quantile( base::abs( .data$empirical_weight - .data$predicted_weight ), probs = 0.25, names = FALSE ), p75_abs_error = stats::quantile( base::abs( .data$empirical_weight - .data$predicted_weight ), probs = 0.75, names = FALSE ) ) 
  
  primary_cv_summary <- cv_rows |> dplyr::filter(.data$is_primary) |> dplyr::summarise( observed_mean = base::mean(.data$empirical_weight), observed_sd = stats::sd(.data$empirical_weight), observed_median = stats::median(.data$empirical_weight), observed_p25 = stats::quantile( .data$empirical_weight, probs = 0.25, names = FALSE ), observed_p75 = stats::quantile( .data$empirical_weight, probs = 0.75, names = FALSE ), predicted_mean = base::mean(.data$predicted_weight), predicted_sd = stats::sd(.data$predicted_weight), predicted_median = stats::median(.data$predicted_weight), predicted_p25 = stats::quantile( .data$predicted_weight, probs = 0.25, names = FALSE ), predicted_p75 = stats::quantile( .data$predicted_weight, probs = 0.75, names = FALSE ) ) 
  log_step( "Cross-validated location-share MAE: ", base::sprintf( "%.3f", cv_metrics$mean_abs_error[[1L]] ) ) 
  
  location_model <- fit_share_model( training_rows, share_formula ) 
  model_coefficients <- broom::tidy( location_model, conf.int = TRUE ) 
  
  national_scores <- canonical_locations |> dplyr::mutate( raw_score = dplyr::if_else( .data$n_locations == 1L, 1, base::pmin( 1 - 1e-6, base::pmax( 1e-6, stats::predict( location_model, newdata = canonical_locations, type = "response" ) ) ) ) ) |> normalize_prediction("raw_score") 
  direct_chia_weights <- training_rows |> dplyr::select( .data$npi, .data$canonical_location_id, direct_chia_weight = .data$empirical_weight ) 
  
  national_weights <- national_scores |> dplyr::left_join( direct_chia_weights, by = base::c( "npi", "canonical_location_id" ) ) |> dplyr::group_by(.data$npi) |> dplyr::mutate( has_direct_chia = base::all( !base::is.na(.data$direct_chia_weight) ), empirical_model_weight = dplyr::case_when( .data$n_locations == 1L ~ 1, .data$has_direct_chia ~ .data$direct_chia_weight, TRUE ~ .data$predicted_weight ), weight_source = dplyr::case_when( .data$n_locations == 1L ~ "single_location", .data$has_direct_chia ~ "CHIA_direct", TRUE ~ "CHIA_calibrated_model" ), primary_only_weight = base::as.numeric( .data$is_primary ), equal_weight = 1 / .data$n_locations, primary_heavy_weight = dplyr::case_when( .data$n_locations == 1L ~ 1, .data$is_primary ~ 0.80, TRUE ~ 0.20 / (.data$n_locations - 1L) ) ) |> dplyr::ungroup() |> dplyr::select( -.data$direct_chia_weight, -.data$has_direct_chia ) 
  
  weight_guard <- national_weights |> dplyr::group_by(.data$npi) |> dplyr::summarise( empirical_sum = base::sum( .data$empirical_model_weight ), primary_sum = base::sum( .data$primary_only_weight ), equal_sum = base::sum(.data$equal_weight), heavy_sum = base::sum( .data$primary_heavy_weight ), .groups = "drop" ) |> dplyr::mutate( max_error = base::pmax( base::abs(.data$empirical_sum - 1), base::abs(.data$primary_sum - 1), base::abs(.data$equal_sum - 1), base::abs(.data$heavy_sum - 1) ) ) 
  if (base::max(weight_guard$max_error) > 1e-10) { base::stop( "At least one NPI violates the sum-to-one capacity constraint." ) } 
  
  if (base::is.null(capacity_path)) { 
    log_step( "No capacity file supplied; assigning 1.0 total FTE per NPI." ) 
    provider_capacity <- national_weights |> dplyr::distinct(.data$npi) |> dplyr::mutate(total_capacity_fte = 1) 
  } else { 
    log_step( "Reading provider capacity file: ", capacity_path ) 
    provider_capacity <- read_small(capacity_path) |> dplyr::transmute( npi = base::as.character( .data[[capacity_map$npi]] ), total_capacity_fte = base::as.numeric( .data[[capacity_map$capacity]] ) ) |> dplyr::filter(.data$npi %in% target_npis) 
    missing_capacity <- national_weights |> dplyr::distinct(.data$npi) |> dplyr::anti_join( provider_capacity, by = "npi" ) 
    if (base::nrow(missing_capacity) > 0L) { 
      capacity_missing_path <- save_csv( missing_capacity, "multisite_missing_capacity", stamp ) 
      base::stop( "Missing capacity for at least one target NPI. See: ", capacity_missing_path ) 
    } 
  } 
  
  e2sfca_locations <- national_weights |> dplyr::left_join( provider_capacity, by = "npi" ) |> dplyr::mutate( capacity_empirical = .data$total_capacity_fte * .data$empirical_model_weight, capacity_primary_only = .data$total_capacity_fte * .data$primary_only_weight, capacity_equal = .data$total_capacity_fte * .data$equal_weight, capacity_primary_heavy = .data$total_capacity_fte * .data$primary_heavy_weight ) 
  
  capacity_guard <- e2sfca_locations |> dplyr::group_by(.data$npi) |> dplyr::summarise( total_capacity_fte = base::max( .data$total_capacity_fte ), empirical_capacity = base::sum( .data$capacity_empirical ), primary_capacity = base::sum( .data$capacity_primary_only ), equal_capacity = base::sum( .data$capacity_equal ), heavy_capacity = base::sum( .data$capacity_primary_heavy ), .groups = "drop" ) |> dplyr::mutate( max_error = base::pmax( base::abs( .data$empirical_capacity - .data$total_capacity_fte ), base::abs( .data$primary_capacity - .data$total_capacity_fte ), base::abs( .data$equal_capacity - .data$total_capacity_fte ), base::abs( .data$heavy_capacity - .data$total_capacity_fte ) ) ) 
  if (base::max(capacity_guard$max_error) > 1e-10) { base::stop( "Mass conservation failed after applying provider capacity." ) } 
  
  medicare_validation <- NULL 
  if (!base::is.null(medicare_path)) { 
    log_step( "Adding NPI-level Medicare utilization validation: ", medicare_path ) 
    medicare_raw <- read_large( medicare_path, medicare_delim ) 
    medicare_validation <- medicare_raw |> dplyr::transmute( npi = base::as.character( .data[[medicare_map$npi]] ), services = base::as.numeric( .data[[medicare_map$services]] ), beneficiary_days = base::as.numeric( .data[[medicare_map$beneficiary_days]] ) ) |> dplyr::filter(.data$npi %in% target_npis) |> dplyr::group_by(.data$npi) |> dplyr::summarise( medicare_services = base::sum( .data$services, na.rm = TRUE ), medicare_beneficiary_days = base::sum( .data$beneficiary_days, na.rm = TRUE ), .groups = "drop" ) |> dplyr::collect() |> dplyr::left_join( national_weights |> dplyr::group_by(.data$npi) |> dplyr::summarise( n_locations = base::max( .data$n_locations ), secondary_share = 1 - .data$empirical_model_weight[ .data$is_primary ][[1L]], weight_source = base::paste( base::unique(.data$weight_source), collapse = "+" ), .groups = "drop" ), by = "npi" ) 
  } 
  
  cadr_validation <- NULL 
  if (!base::is.null(cadr_path)) { 
    log_step( "Adding CADR facility/location validation: ", cadr_path ) 
    cadr_raw <- read_small( cadr_path, cadr_delim ) 
    if (base::is.null(cadr_map$address2)) { 
      cadr_raw <- cadr_raw |> dplyr::mutate(.address2 = NA_character_) 
      cadr_address2_col <- ".address2" 
    } else { 
      cadr_address2_col <- cadr_map$address2 
    } 
    cadr_rows <- cadr_raw |> dplyr::transmute( npi = base::as.character( .data[[cadr_map$npi]] ), address1 = base::as.character( .data[[cadr_map$address1]] ), address2 = base::as.character( .data[[cadr_address2_col]] ), city = base::as.character( .data[[cadr_map$city]] ), state = base::as.character( .data[[cadr_map$state]] ), zip = base::as.character( .data[[cadr_map$zip]] ), service_date = lubridate::ymd( base::as.character( .data[[cadr_map$service_date]] ), quiet = TRUE ) ) |> dplyr::filter(.data$npi %in% target_npis) |> dplyr::mutate( zip5 = normalize_zip(.data$zip), address_key = make_address_key( .data$address1, .data$address2, .data$city, .data$state, .data$zip ) ) 
    cadr_exact <- cadr_rows |> dplyr::inner_join( national_weights |> dplyr::select( .data$npi, .data$address_key, .data$canonical_location_id, .data$empirical_model_weight, .data$is_primary ), by = base::c( "npi", "address_key" ) ) |> dplyr::mutate( match_method = "exact_address" ) 
    cadr_unmatched <- cadr_rows |> dplyr::anti_join( cadr_exact |> dplyr::select( .data$npi, .data$address_key ), by = base::c( "npi", "address_key" ) ) 
    national_unique_zip <- national_weights |> dplyr::group_by( .data$npi, .data$zip5 ) |> dplyr::filter( !base::is.na(.data$zip5), dplyr::n() == 1L ) |> dplyr::ungroup() |> dplyr::select( .data$npi, .data$zip5, .data$canonical_location_id, .data$empirical_model_weight, .data$is_primary ) 
    cadr_zip <- cadr_unmatched |> dplyr::inner_join( national_unique_zip, by = base::c( "npi", "zip5" ) ) |> dplyr::mutate( match_method = "unique_npi_zip" ) 
    cadr_validation <- dplyr::bind_rows( cadr_exact, cadr_zip ) |> dplyr::group_by( .data$npi, .data$canonical_location_id, .data$empirical_model_weight, .data$is_primary, .data$match_method ) |> dplyr::summarise( cadr_days = dplyr::n_distinct( .data$service_date ), .groups = "drop" ) 
  } 
  
  observed_years <- location_day_intensity |> dplyr::summarise( min_year = base::min( lubridate::year(.data$service_date) ), max_year = base::max( lubridate::year(.data$service_date) ) ) 
  primary_direct_summary <- training_rows |> dplyr::filter(.data$is_primary) |> dplyr::summarise( mean = base::mean(.data$empirical_weight), sd = stats::sd(.data$empirical_weight), median = stats::median(.data$empirical_weight), p25 = stats::quantile( .data$empirical_weight, 0.25, names = FALSE ), p75 = stats::quantile( .data$empirical_weight, 0.75, names = FALSE ) ) 
  log_step( "CHIA years ", observed_years$min_year[[1L]], "-", observed_years$max_year[[1L]], "; empirical primary-location share mean ", base::sprintf( "%.3f", primary_direct_summary$mean[[1L]] ), " (SD ", base::sprintf( "%.3f", primary_direct_summary$sd[[1L]] ), "), median ", base::sprintf( "%.3f", primary_direct_summary$median[[1L]] ), " (p25 ", base::sprintf( "%.3f", primary_direct_summary$p25[[1L]] ), ", p75 ", base::sprintf( "%.3f", primary_direct_summary$p75[[1L]] ), ")." ) 
  
  path_weights <- save_csv( national_weights, "national_multisite_location_weights", stamp ) 
  path_e2sfca <- save_csv( e2sfca_locations, "e2sfca_weighted_supply_locations", stamp ) 
  path_training <- save_csv( training_rows, "chia_multisite_training_rows", stamp ) 
  path_unmatched <- save_csv( unresolved_sites, "chia_unmatched_observed_sites", stamp ) 
  path_cv <- save_csv( cv_metrics, "multisite_cross_validation_metrics", stamp ) 
  path_primary_cv <- save_csv( primary_cv_summary, "multisite_primary_share_cv", stamp ) 
  path_coefficients <- save_csv( model_coefficients, "multisite_model_coefficients", stamp ) 
  path_mass_guard <- save_csv( capacity_guard, "multisite_mass_conservation_guard", stamp ) 
  if (!base::is.null(medicare_validation)) { path_medicare <- save_csv( medicare_validation, "multisite_medicare_validation", stamp ) } else { path_medicare <- NA_character_ } 
  if (!base::is.null(cadr_validation)) { path_cadr <- save_csv( cadr_validation, "multisite_cadr_validation", stamp ) } else { path_cadr <- NA_character_ } 
  
  log_step("Completed empirical multi-location weighting.") 
  log_step("Preferred E2SFCA file: ", path_e2sfca) 
  
  bundle <- list( 
    allocation_model = location_model, 
    model_coefficients = model_coefficients, 
    national_weights = national_weights, 
    e2sfca_locations = e2sfca_locations, 
    training_rows = training_rows, 
    unresolved_sites = unresolved_sites, 
    cv_metrics = cv_metrics, 
    primary_cv_summary = primary_cv_summary, 
    medicare_validation = medicare_validation, 
    cadr_validation = cadr_validation, 
    paths = list( weights = path_weights, e2sfca = path_e2sfca, training = path_training, unmatched = path_unmatched, cross_validation = path_cv, primary_cross_validation = path_primary_cv, coefficients = path_coefficients, mass_guard = path_mass_guard, medicare = path_medicare, cadr = path_cadr ) 
  ) 
  base::invisible(bundle) 
} 
