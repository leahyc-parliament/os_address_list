# OS Master Address List

## Overview

This script transforms the OS's master address list for Great Britain into usable csv's split by region.  

The workflow uses DuckDB to efficiently process the large 17.6GB csv without having to load the whole thing into RAM.

## Workflow
1. Read lookups and address list dataset into DuckDB
2. Join addresses to region by local authority code
3. Write intermediate csvs split by region
4. Join addresses in each csv to a constituency using sf's point_in_polygon with address co-ordinates and constituency polygons
5. Write final csvs

## Inputs

The script requires:

### OS Master Address List

https://osdatahub.os.uk/data/downloads/data-packages/18300

```text
add_gb_builtaddress.csv
```

### Local Authority to Region Lookup

```text
lookups/constituency_la_region_country.csv
```

### Westminster Constituency Boundaries

```text
geopackages/Westminster_Parliamentary_Constituencies_July_2024_Boundaries_UK_BUC_*.gpkg
```

## Outputs

### Intermediate Regional Files

```
regional_abs/
```

Addresses are joined by local authority codes to regions, and are then split into separate CSV files by region.

### Final Files
```
ab_final/
```

Addresses in the intermediate regional files are then joined by co-ordinates to constituency polygons using the sf package.


# Notes

- 0.01% of addresses cannot be joined to a region or constituency. This is either due to NULL co-ordinates, NULL local authority codes, or incorrect legacy local authority codes. 
- Addresses that cannot be assigned a region are removed before processing.
