import requests
import json
import boto3
import subprocess
def find_existing_folder(api_url, api_key, folder_name):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "Content-Type": "application/json"
    }

    response = requests.get(f"{api_url}/folders", headers=headers)

    if response.status_code == 200:
        folders = response.json()
        for folder in folders:
            if folder.get("title") == folder_name:
                return folder.get("id")
        
        # If no matching folder is found, return None
        return None
    else:
        print(f"Failed to fetch folders. Status Code: {response.status_code}")
        return None

def replace_in_dict(obj, search, replacement):
    if isinstance(obj, dict):
        for key in list(obj.keys()):
            obj[key] = replace_in_dict(obj[key], search, replacement)
        return obj
    elif isinstance(obj, list):
        return [replace_in_dict(item, search, replacement) for item in obj]
    elif isinstance(obj, str):
        return obj.replace(search, replacement)
    else:
        return obj

print('Settting up variables')

maxion_grafana_url = "https://maxion.tvarit.com/api"
cloud_grafana_url = "https://cloud.tvarit.com/api"
test_grafana_url = "https://test.tvarit.com/api"
grafana_url = ""

aws_cli_command = "aws secretsmanager get-secret-value --secret-id /credentials/grafana-user/access-key --output text --query SecretString"

try:
    # Run the AWS CLI command and capture its output
    result = subprocess.run(aws_cli_command, shell=True, text=True, capture_output=True, check=True)
    secret_json = json.loads(result.stdout)
    
    data = secret_json
except subprocess.CalledProcessError as e:
    # Handle any errors or exceptions here
    print("AWS CLI command failed with error:")
    print(e.stderr)

print('###################################Starting Deployment###################################')

data_test = data.get("Test", {})

for key in data_test.keys():
    print('Deploying in ',key)
    if key in ['Alcar', 'Gienanth', 'Procast', 'Voit', 'Doktas', 'ESW', 'Endurance', 'Foehl', 'Mahle', 'Mbusch']:
        grafana_url = cloud_grafana_url
    else:
        grafana_url = maxion_grafana_url
    org_data = data_test[key]
    # org_data['api'] = {f'TEST_API_KEY_{key}'}
    headers = {
        "Authorization": f"Bearer {org_data['api']}"
    }

    data_prod = data.get("Prod", {}).get(key, {})
    api = data_prod['api']
    headers2 = {
            "Authorization": f"Bearer {api}",
            "Accept": "application/json",
            "Content-Type": "application/json",
    }
    for folder in ['Production Dashboards PsQ', 'Production Dashboards PsE']:
        source_folder = find_existing_folder(test_grafana_url, org_data['api'], folder)
        destination_folder = find_existing_folder(grafana_url, api, folder)
        if source_folder and destination_folder:
            print(source_folder, destination_folder)
            response = requests.get(f"{test_grafana_url}/search", params={"folderIds": [source_folder]}, headers=headers)
            dashboards_response = response.json()
            print(dashboards_response)
            for dashboard in dashboards_response:
                    dashboard_uid = dashboard["uid"]
                    dashboard_title = dashboard["title"]

                    # Add functionality for versioning
                    print(f"Dashboard '{dashboard_title}' has a new version.")
                    # print(dashboard)
                    # Step 5: Retrieve Dashboard JSON
                    response = requests.get(f"{test_grafana_url}/dashboards/uid/{dashboard_uid}", headers=headers)
                    # print(response)
                    
                    dashboard_json = response.json()
                    
                    for key in org_data.keys():
                        if key in data_prod:
                            replace_in_dict(dashboard_json, org_data[key], data_prod[key])
                    # print("Dashboard JSON")
                    # print(dashboard_json)
                    dashboard = dashboard_json.get("dashboard", {})
                    del dashboard["uid"]
                    # dashboard["version"] = "1"
                    del dashboard["id"]
                    if 'meta' in dashboard_json:
                        del dashboard_json['meta']
                    # print(dashboard)
                    dashboard_json["dashboard"] = dashboard
                    dashboard_json["overwrite"] = True
                    dashboard_json["folderId"] = destination_folder

                    print(f'Uploading to ${grafana_url}')
                    response = requests.post(f"{grafana_url}/dashboards/db", headers=headers2, json=dashboard_json)
                    if response.status_code == 200:
                        print("Dashboard creation/updating successful!")
                    else:
                        print(f"Error {response.status_code}: {response.content.decode('utf-8')}")
        else:
            print(f'Could not find folder {folder} in org {key}')



