# CONUS bounding-box gate (48 states + DC; excludes AK/HI/PR/territories).

Matches \`conus_ok()\` in the scripts: lon in (-125, -66), lat in (24,
50).

## Usage

``` r
dj7_conus_ok(lat, lon)
```

## Arguments

- lat, lon:

  numeric vectors.

## Value

logical vector; NA coordinates are FALSE.
