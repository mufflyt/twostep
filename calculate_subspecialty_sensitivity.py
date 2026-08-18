import pandas as pd

df = pd.read_csv("manuscript/data/longitudinal_secondary_locations_abog.csv", dtype=str)

df['Primary_Zip'] = df['Primary_Zip'].astype(str).str[:5]
df['Secondary_Zip'] = df['Secondary_Zip'].astype(str).str[:5]

# Filter out non-contiguous US states
non_contiguous = ['AK', 'HI', 'PR', 'GU', 'VI', 'AS', 'MP']
df = df[~df['Primary_State'].isin(non_contiguous)]
df = df[~df['Secondary_State'].isin(non_contiguous)]

# Filter for 2024
df = df[df['Year'] == '2024']

subspecialties = ['MFM', 'REI', 'ONC', 'FPM', 'MIG', 'PAG']
full_names = {
    'MFM': 'Maternal-Fetal Medicine',
    'REI': 'Reproductive Endocrinology and Infertility',
    'ONC': 'Gynecologic Oncology',
    'FPM': 'Urogynecology',
    'MIG': 'Minimally Invasive Gynecologic Surgery',
    'PAG': 'Pediatric and Adolescent Gynecology'
}

results = []

for sub in subspecialties:
    sub_df = df[df['Subspecialty'] == sub]
    
    total_docs = sub_df['NPI'].nunique()
    
    primary_zips = set(sub_df[sub_df['Primary_Zip'].notnull()]['Primary_Zip'].unique())
    
    sec_df = sub_df[sub_df['Secondary_Zip'].notnull() & (sub_df['Secondary_Zip'] != 'nan') & (sub_df['Secondary_Zip'] != '') & (sub_df['Secondary_Zip'] != sub_df['Primary_Zip'])]
    
    docs_with_satellite = sec_df['NPI'].nunique()
    
    satellite_zips = set(sec_df['Secondary_Zip'].unique())
    new_access_zips = satellite_zips - primary_zips
    
    docs_in_new_deserts = sec_df[sec_df['Secondary_Zip'].isin(new_access_zips)]['NPI'].nunique()
    
    if total_docs > 0:
        percent_with_satellite = round((docs_with_satellite / total_docs) * 100, 1)
    else:
        percent_with_satellite = 0.0
        
    results.append({
        'Subspecialty': full_names[sub],
        'Total_Subspecialists': total_docs,
        'Docs_with_Satellite_Clinic': docs_with_satellite,
        'Percent_with_Satellite': percent_with_satellite,
        'Satellite_Clinics_in_New_Access_Deserts': len(new_access_zips),
        'Docs_Serving_New_Access_Deserts': docs_in_new_deserts
    })

md_table = "| Subspecialty | Total Subspecialists | Docs w/ Satellite Clinic | % with Satellite | Satellite Clinics in New Access Deserts | Docs Serving New Deserts |\n"
md_table += "| --- | --- | --- | --- | --- | --- |\n"
results.sort(key=lambda x: x['Percent_with_Satellite'], reverse=True)

for r in results:
    md_table += f"| {r['Subspecialty']} | {r['Total_Subspecialists']} | {r['Docs_with_Satellite_Clinic']} | {r['Percent_with_Satellite']}% | {r['Satellite_Clinics_in_New_Access_Deserts']} | {r['Docs_Serving_New_Access_Deserts']} |\n"

print("--- Subspecialty Sensitivity (2024) ---")
print(md_table)
with open("subspecialty_metrics_2024.md", "w") as f:
    f.write(md_table)
