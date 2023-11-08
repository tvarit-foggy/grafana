import requests
import json
import datetime
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

def get_last_run(bucket_name, prefix):
    try:
        # Use the AWS CLI to list objects in the S3 bucket and prefix
        aws_cli_command = f"aws s3 ls s3://{bucket_name}/{prefix}"
        result = subprocess.check_output(aws_cli_command, shell=True).decode("utf-8")

        # Split the result into lines and extract folder names
        lines = result.splitlines()
        folder_names = [line.split()[-1].rstrip('/') for line in lines if line.endswith('/')]

        if not folder_names:
            print("No folders found in the specified prefix.")
            return None

        # Sort folder names in descending order (latest first)
        folder_names.sort(reverse=True)

        # Extract the latest folder name
        latest_folder_name = folder_names[0]

        return latest_folder_name
    except subprocess.CalledProcessError as e:
        print(f"Error listing S3 objects: {e}")
        return None

def upload_release_notes_to_s3(versioning_info, bucket_name, s3_key): 
    # Create a temporary text file to store the filtered response
    with open("release-notes.txt", "w") as file:
        for entry in versioning_info:
            print(entry)
            file.write(f"{entry}\n")
    # Use the AWS CLI to upload the file to the specified S3 bucket
    aws_cli_command = f'aws s3 cp release-notes.txt "s3://{bucket_name}/{s3_key}/release-notes.txt"'
    try:
        subprocess.run(aws_cli_command, shell=True, check=True)
        print(f"Release Notes uploaded to S3: s3://{bucket_name}/{s3_key}")
    except subprocess.CalledProcessError as e:
        print(f"Error uploading to S3: {e}")
    finally:
        # Clean up the temporary file
        subprocess.run("rm release-notes.txt", shell=True)

print('Settting up variables')

maxion_grafana_url = "https://maxion.tvarit.com/api"
cloud_grafana_url = "https://cloud.tvarit.com/api"
test_grafana_url = "https://test.tvarit.com/api"
grafana_url = ""

aws_cli_command = "aws secretsmanager get-secret-value --secret-id grafana-deployment-api --output text --query SecretString"

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
            # print(dashboards_response)
            for dashboard in dashboards_response:
                    dashboard_uid = dashboard["uid"]
                    dashboard_title = dashboard["title"]
                    dashboard_id = dashboard["id"]
                    
                    response = requests.get(f'{test_grafana_url}/dashboards/id/{dashboard_id}/versions', headers=headers)
                    response = json.loads(response.content.decode('utf-8'))
                    print(response)
                    last_run = get_last_run('tvarit.product.releasenotes','')
                    if last_run:
                        last_run=datetime.datetime.strptime(last_run, "%Y-%m-%dT%H:%M:%S.%f")
                        filtered_response = []
                        for entry in response:
                            if "created" in entry:
                                try:
                                    created_datetime = datetime.datetime.strptime(entry["created"], "%Y-%m-%dT%H:%M:%SZ")
                                    if created_datetime > last_run:
                                        filtered_response.append(entry)
                                except ValueError as e:
                                    print(f"Error parsing 'created' field: {e}")
                    current_datetime = datetime.datetime.now().isoformat()
                    upload_release_notes_to_s3(filtered_response, 'tvarit.product.releasenotes', f'{current_datetime}/{key}/{folder}/{dashboard_title}')
                    
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

                    print(f'Uploading to {grafana_url}')
                    response = requests.post(f"{grafana_url}/dashboards/db", headers=headers2, json=dashboard_json)
                    if response.status_code == 200:
                        print("Dashboard creation/updating successful!")
                    else:
                        print(f"Error {response.status_code}: {response.content.decode('utf-8')}")
        else:
            print(f'Could not find folder {folder} in org {key}')



