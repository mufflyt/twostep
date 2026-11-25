# Parse a "lat_lon" coord_id into numeric latitude/longitude.

coord_ids are the E2SFCA origin keys, e.g. "39.73921\_-104.99025". A
malformed key (no underscore, non-numeric) yields NA for the affected
field rather than an error.

## Usage

``` r
dj7_parse_coord_id(coord_id)
```

## Arguments

- coord_id:

  character vector.

## Value

data.frame(coord_id, lat, lon).
