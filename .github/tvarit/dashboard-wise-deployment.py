import requests
import json
import datetime
import copy
import os
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
        file.write(f"{versioning_info}\n")
    # Use the AWS CLI to upload the file to the specified S3 bucket
    aws_cli_command = f'aws s3 cp release-notes.txt "s3://{bucket_name}/{s3_key}"'
    try:
        subprocess.run(aws_cli_command, shell=True, check=True)
        print(f"Release Notes uploaded to S3: s3://{bucket_name}/{s3_key}")
    except subprocess.CalledProcessError as e:
        print(f"Error uploading to S3: {e}")
    finally:
        # Clean up the temporary file
        subprocess.run("rm release-notes.txt", shell=True)

def format_release_notes(data):
    release_notes = []

    for entry in data:
        version = entry["version"]
        created_by = entry["createdBy"]
        created_date = datetime.datetime.strptime(entry["created"], "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%d %H:%M:%S")
        message = entry["message"]

        release_notes.append(f"Version {version} - {created_date} by {created_by}\n\t- {message}")

    return "\n\n".join(release_notes)

def translate_text(text, target_language):
    url = 'https://api-free.deepl.com/v2/translate'
    headers = {'Authorization': f'DeepL-Auth-Key {deepl_key}'}
    
    if '$' in text:  # Check if text contains '$'
        words = text.split()  # Split text into words
        translated_words = []
        for word in words:
            if word.startswith('$'):
                translated_words.append(word)  # Append words starting with '$' as they are
            else:
                payload = {
                    'text': word,
                    'target_lang': target_language
                }
                response = requests.post(url, headers=headers, data=payload)
                if response.status_code == 200:
                    translation = response.json()
                    translated_word = translation['translations'][0]['text']
                    translated_words.append(translated_word)
                else:
                    return f"Translation failed with status code {response.status_code}"
        return ' '.join(translated_words)  # Join translated and non-translated words
    else:
        payload = {
            'text': text,
            'target_lang': target_language
        }
        response = requests.post(url, headers=headers, data=payload)
        if response.status_code == 200:
            translation = response.json()
            return translation['translations'][0]['text']
        else:
            return f"Translation failed with status code {response.status_code}"


def translate_titles(data, target_language):
     
    if isinstance(data, dict):
        for key, value in data.items():
            if key == 'title':
                data[key] = translate_text(value, target_language)
            else:
                translate_titles(value, target_language)
    elif isinstance(data, list):
        for item in data:
            translate_titles(item, target_language)


def translate_enclosed_text(data, target_language):
    if isinstance(data, dict):
        for key, value in data.items():
            data[key] = translate_enclosed_text(value, target_language)
    elif isinstance(data, list):
        for i, item in enumerate(data):
            data[i] = translate_enclosed_text(item, target_language)
    elif isinstance(data, str):
        start_tag = '/*<t>*/'
        end_tag = '/*</t>*/'
        start_index = data.find(start_tag)
        while start_index != -1:
            end_index = data.find(end_tag, start_index + len(start_tag))
            if end_index != -1:
                enclosed_text = data[start_index + len(start_tag):end_index]
                translated_text = translate_text(enclosed_text, target_language)
                # Add single quotes around the translated text
                translated_text = f"{translated_text}"
                data = data.replace(start_tag + enclosed_text + end_tag, translated_text)
                start_index = data.find(start_tag, end_index + len(end_tag))
            else:
                break
    return data



print('Setting up variables')

maxion_grafana_url = "https://maxion.tvarit.com/api"
cloud_grafana_url = "https://cloud.tvarit.com/api"
test_grafana_url = "https://test.tvarit.com/api"
grafana_url = ""

deepl_key = os.environ.get('DEEPL_API_KEY')
input_orgs = os.environ.get('INPUT_ORGS').split(',')
input_dashboard_uid = os.environ.get('INPUT_DASHBOARD_UID')
input_orgs = [key.upper() for key in input_orgs]
aws_cli_command = "aws secretsmanager get-secret-value --secret-id grafana-deployment-api --output text --query SecretString"
print(input_orgs)
try:
    # Run the AWS CLI command and capture its output
    result = subprocess.run(aws_cli_command, shell=True, text=True, capture_output=True, check=True)
    secret_json = json.loads(result.stdout)
    
    data = secret_json
except subprocess.CalledProcessError as e:
    # Handle any errors or exceptions here
    print("Secrets Manager command failed with error:")
    print(e.stderr)

print('###################################Starting Deployment###################################')

data_test = {
    key: value for key, value in data["Test"].items() if key.upper() in input_orgs
}
current_datetime = datetime.datetime.now().isoformat()
for key in data_test.keys():
    print('Deploying in ',key)
    if key in ['Alcar', 'Gienanth', 'Procast', 'Voit', 'Doktas', 'ESW', 'Endurance', 'Foehl', 'Mahle', 'Mbusch', 'UnoMinda']:
        grafana_url = cloud_grafana_url
    else:
        grafana_url = maxion_grafana_url
    org_data = data_test[key]
    # org_data['api'] = {f'TEST_API_KEY_{key}'}
    headers = {
        "Authorization": f"Bearer {org_data['api']}"
    }
    org = key
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
            # print(source_folder, destination_folder)
            response = requests.get(f"{test_grafana_url}/search", params={"folderIds": [source_folder]}, headers=headers)
            dashboards_response = response.json()
            # print(dashboards_response)
            for dashboard in dashboards_response:
                if str(input_dashboard_uid) == dashboard["uid"]:
                    dashboard_uid = dashboard["uid"]
                    dashboard_title = dashboard["title"]
                    dashboard_id = dashboard["id"]
                    
                    response = requests.get(f'{test_grafana_url}/dashboards/id/{dashboard_id}/versions', headers=headers)
                    response = json.loads(response.content.decode('utf-8'))
                    print(response)
                    last_run = get_last_run('tvarit.product.releasenotes',{org})
                    filtered_response = []
                    if last_run:
                        last_run=datetime.datetime.strptime(last_run, "%Y-%m-%dT%H:%M:%S.%f")
                        for entry in response:
                            if "created" in entry:
                                try:
                                    created_datetime = datetime.datetime.strptime(entry["created"], "%Y-%m-%dT%H:%M:%SZ")
                                    if created_datetime > last_run:
                                        filtered_response.append(entry)
                                except ValueError as e:
                                    print(f"Error parsing 'created' field: {e}")
                    
                    else:
                        filtered_response = response
                    
                    print(filtered_response)
                    notes = format_release_notes(filtered_response)
                    
                    upload_release_notes_to_s3(notes, 'tvarit.product.releasenotes', f'{org}/{current_datetime}/{folder}/{dashboard_title}-release-notes.txt')
                    
                    # Add functionality for versioning
                    print(f"Dashboard '{dashboard_title}' has a new version.")
                    # print(dashboard)
                    # Step 5: Retrieve Dashboard JSON
                    response = requests.get(f"{test_grafana_url}/dashboards/uid/{dashboard_uid}", headers=headers)
                    # print(response)
                    
                    dashboard_json = response.json()
                    all_dashboards = []
                    for key in org_data.keys():
                        if key in data_prod:
                            replace_in_dict(dashboard_json, org_data[key], data_prod[key])
                    all_dashboards.append(copy.deepcopy(dashboard_json))  # Append a deepcopy

                    # Translate dashboards
                    translate_flag = org_data.get("language", [])
                    if translate_flag and len(translate_flag) > 0:
                        dashboard_json_translated = copy.deepcopy(dashboard_json)  # Create an independent copy

                        for language in org_data['language']:
                            translate_titles(dashboard_json_translated, language)
                            dashboard_json_translated = translate_enclosed_text(dashboard_json_translated, language)
                            all_dashboards.append(copy.deepcopy(dashboard_json_translated))  # Append a deepcopy

                    print(all_dashboards)
                    for dash in all_dashboards:
                        dashboard = dash.get("dashboard", {})
                        print(dashboard)
                        del dashboard["uid"]
                        # dashboard["version"] = "1"
                        del dashboard["id"]
                        if 'meta' in dash:
                            del dash['meta']
                        # print(dashboard)
                        dash["dashboard"] = dashboard
                        dash["overwrite"] = True
                        dash["folderId"] = destination_folder

                        print(f'Uploading to {grafana_url}')
                        response = requests.post(f"{grafana_url}/dashboards/db", headers=headers2, json=dash)
                        if response.status_code == 200:
                            print("Dashboard creation/updating successful!")
                        else:
                            print(f"Error {response.status_code}: {response.content.decode('utf-8')}")
        else:
            print(f'Could not find folder {folder} in org {key}')



