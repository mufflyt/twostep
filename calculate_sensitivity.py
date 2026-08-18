import pandas as pd

df = pd.read_csv("manuscript/data/longitudinal_secondary_locations_abog.csv", dtype=str)

# Clean zips
df['Primary_Zip'] = df['Primary_Zip'].astype(str).str[:5]
df['Secondary_Zip'] = df['Secondary_Zip'].astype(str).str[:5]

# Filter out non-contiguous US states
non_contiguous = ['AK', 'HI', 'PR', 'GU', 'VI', 'AS', 'MP']
df = df[~df['Primary_State'].isin(non_contiguous)]
df = df[~df['Secondary_State'].isin(non_contiguous)]

years = df['Year'].unique()
years.sort()

results = []

for year in years:
    year_df = df[df['Year'] == year]
    
    total_docs = year_df['NPI'].nunique()
    
    primary_zips = set(year_df[year_df['Primary_Zip'].notnull()]['Primary_Zip'].unique())
    
    sec_df = year_df[year_df['Secondary_Zip'].notnull() & (year_df['Secondary_Zip'] != 'nan') & (year_df['Secondary_Zip'] != '') & (year_df['Secondary_Zip'] != year_df['Primary_Zip'])]
    
    docs_with_satellite = sec_df['NPI'].nunique()
    
    satellite_zips = set(sec_df['Secondary_Zip'].unique())
    new_access_zips = satellite_zips - primary_zips
    
    docs_in_new_deserts = sec_df[sec_df['Secondary_Zip'].isin(new_access_zips)]['NPI'].nunique()
    
    results.append({
        'Year': year,
        'Total_Subspecialists': total_docs,
        'Docs_with_Satellite_Clinic': docs_with_satellite,
        'Percent_with_Satellite': round((docs_with_satellite / total_docs) * 100, 1),
        'Satellite_Clinics_in_New_Access_Deserts': len(new_access_zips),
        'Docs_Serving_New_Access_Deserts': docs_in_new_deserts
    })

md_table = "| Year | Total Subspecialists | Docs w/ Satellite Clinic | % with Satellite | Satellite Clinics in New Access Deserts | Docs Serving New Deserts |\n"
md_table += "| --- | --- | --- | --- | --- | --- |\n"
for r in results:
    md_table += f"| {r['Year']} | {r['Total_Subspecialists']} | {r['Docs_with_Satellite_Clinic']} | {r['Percent_with_Satellite']}% | {r['Satellite_Clinics_in_New_Access_Deserts']} | {r['Docs_Serving_New_Access_Deserts']} |\n"

print("--- Overall Sensitivity ---")
print(md_table)
with open("sensitivity_metrics.md", "w") as f:
    f.write(md_table)
