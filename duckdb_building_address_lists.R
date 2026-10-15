library(DBI)
library(duckdb)
library(dplyr)
library(sf)
library(data.table)

# make necessary folders
dir.create(
  "regional_abs"
)
dir.create(
  "ab_final"
)

# open DuckDB connetion
con <- dbConnect(duckdb())

# ONS geography lookups
la_to_region <- read.csv(
  "lookups/constituency_la_region_country.csv"
) |>
  select(local_authority_code, local_authority_name, region_code, region_name) |> 
  distinct()

# add region lookup to DuckDB
dbWriteTable(
  con,
  "la_to_region",
  la_to_region,
  overwrite = TRUE
)

# join data to region by local authority code
dbExecute(
  con,
  "
  CREATE TABLE addresses_with_region AS

  SELECT
      a.*,
      r.local_authority_name,
      r.region_code,
      r.region_name

  FROM read_csv_auto(
      'add_gb_builtaddress.csv'
  ) a

  LEFT JOIN la_to_region r
      ON a.lowertierlocalauthoritygsscode =
         r.local_authority_code
  "
)

# check regions
dbGetQuery(
  con,
  "
  SELECT DISTINCT region_name
  FROM addresses_with_region
  ORDER BY region_name
  "
)

# check how many weren't assigned to a region
dbGetQuery(
  con,
  "
  SELECT COUNT(*)
  FROM addresses_with_region
  WHERE region_name IS NULL
  "
)

# see which LA's weren't assigned to a region 
# (only 0.01% addresses not assigned - either due to LA's not existing anymore or LA code missing from dataset)
dbGetQuery(
  con,
  "
  SELECT
    lowertierlocalauthoritygsscode,
    COUNT(*) AS n
  FROM addresses_with_region
  WHERE region_name IS NULL
  GROUP BY lowertierlocalauthoritygsscode
  ORDER BY n DESC
  LIMIT 100
  "
)

# removing addresses with NULL region
dbExecute(
  con,
  "
  DELETE FROM addresses_with_region
  WHERE region_name IS NULL
  "
)

# lookup table for file names
region_lookup <- c(
  "East of England" = "ee",
  "East Midlands" = "em",
  "London" = "ln",
  "North East" = "ne",
  "North West" = "nw",
  "South East" = "se",
  "South West" = "sw",
  "West Midlands" = "wm",
  "Yorkshire and The Humber" = "yh",
  "Scotland" = "sc",
  "Wales" = "wa"
)

# splitting into csvs based on region
for (region_name in names(region_lookup)) {
  code <- region_lookup[[region_name]]

  sql <- sprintf(
    "
    COPY (

      SELECT 
        uprn,
        classificationcode,
        hierarchylevel,
        easting,
        northing,
        longitude,
        latitude,
        geometry,
        postcode,
        fulladdress,
        streetname,
        locality,
        townname,
        localcustodiandescription,
        effectiveenddate,
        local_authority_name,
        region_code,
        region_name

      FROM addresses_with_region
      WHERE region_name = '%s'

    )

    TO 'regional_abs/ab_%s.csv'
    (HEADER, DELIMITER ',')

    ",
    region_name,
    code
  )

  dbExecute(con, sql)
}



################## JOINING TO CONSTITUENCY ######################

# const_boundaries <- st_read("geopackages/Westminster_Parliamentary_Constituencies_July_2024_Boundaries_UK_BUC_2763307678252453745.gpkg")

# ee <- dbGetQuery(
#   con,
#   "
#   SELECT *
#   FROM read_csv_auto('regional_abs/ab_ee.csv')
#   "
# )

# ee_sf <- st_as_sf(
#   ee,
#   coords = c("easting", "northing"),
#   crs = 27700
# )

# ee_joined <- st_join(
#   ee_sf,
#   const_boundaries[, c("PCON24CD", "PCON24NM")]
# )

# data.table::fwrite(
#   st_drop_geometry(ee_joined),
#   "regional_abs_const/ab_ee.csv"
# )

# ONS const boundaries gpkg
const_boundaries <- st_read("geopackages/Westminster_Parliamentary_Constituencies_July_2024_Boundaries_UK_BUC_2763307678252453745.gpkg")

# function to join data to constituencies using point in polygon (coords to const bounds polygons)
add_constituencies <- function(region_code,
                               con,
                               const_boundaries,
                               input_dir = "regional_abs",
                               output_dir = "ab_final") {

  input_file <- file.path(
    input_dir,
    paste0("ab_", region_code, ".csv")
  )

  output_file <- file.path(
    output_dir,
    paste0("ab_", region_code, ".csv")
  )

  message("Processing: ", input_file)

  addresses <- dbGetQuery(
    con,
    sprintf(
      "
      SELECT *
      FROM read_csv_auto('%s')
      ",
      gsub("\\\\", "/", input_file)
    )
  )

  addresses_sf <- st_as_sf(
    addresses,
    coords = c("easting", "northing"),
    crs = 27700
  )

  addresses_joined <- st_join(
    addresses_sf,
    const_boundaries[, c("PCON24CD", "PCON24NM")]
  )

  fwrite(
    st_drop_geometry(addresses_joined),
    output_file
  )

  message("Finished: ", output_file)
}

# region short codes
regions <- c(
  "ee",
  "em",
  "ln",
  "ne",
  "nw",
  "sc",
  "se",
  "sw",
  "wa",
  "wm",
  "yh"
)

#calling function to write final datasets
for (region in regions) {

  add_constituencies(
    region_code = region,
    con = con,
    const_boundaries = const_boundaries
  )

}
