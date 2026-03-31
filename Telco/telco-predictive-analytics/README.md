# Telco Predictive Analytics

![Real-Time Machine Learning](images/ml.png)

This demo showcases the application of Flink ML function and Tableflow to enable quick analytics of Telco data in AWS Quicksight.

## **Agenda**
1. [Setup Prerequisites](#step-1)
2. [Project Initalization](#step-2)
3. [Set Credentials & Variables](#step-3)
4. [Deployment](#step-4)
5. [Add-On Setup](#step-5)
6. [Build Quicksight Analytics](#step-6)
7. [Cleanup](#step-7)

![Architecture](images/arch.png) 

## <a name="step-1"></a>Setup Prerequisites
Required tools :
  - `Terraform`
  - `Docker`

Credentials & Access:
  - `AWS Access Keys`
  - `Confluent Cloud API Keys (Confluent Cloud Resource Manager)\nNOTE: for internal user please use user account instead of service account`
  - `AWS Quicksight Access`

## <a name="step-2"></a>Project Initalization
  - Clone Source Code
    
    ```bash
    git clone https://github.com/confluentinc/global-scale-demos.git
    cd global-scale-demos/Telco/telco-predictive-analytics
    ```

  - Initialize terraform and install required providers
    ```bash
    terraform init
    ```

  - Pull docker image for Postgres table initialization
    ```bash
    docker image pull postgres:16
    ```



## <a name="step-3"></a>Set Credentials & Variables
  ```bash

    # Update these variables
    
    #Required Always
    export TF_VAR_project_name="changeme-demo"
    export TF_VAR_confluent_cloud_api_key="<Confluent Cloud Resource Management API Key Name>"
    export TF_VAR_confluent_cloud_api_secret="<Confluent Cloud Resource Management API Key Secret>"
    export AWS_ACCESS_KEY_ID="<AWS User API Key ID>"
    export AWS_SECRET_ACCESS_KEY="<AWS User API Key Secret>"
    export AWS_SESSION_TOKEN="<AWS User Session Token>"
    export TF_VAR_aws_region="us-west-2"
    export TF_VAR_qs_username="<AWS Quicksight User ID>"
  ```
> [!TIP]
> The Quicksight username can be found in Account Info. The format for internal user should be AWSReservedSSO_nonprod-administrator_xxxxx/abc@confluent.io

## <a name="step-4"></a>Deployment
- Verify the resources
  ```bash
  terraform plan
  ```
- Deploy the resources
  ```bash
  terraform apply
  ```
> [!NOTE]
> This will take approx 15 minutes to deploy resources over AWS & Confluent

## <a name="step-5"></a>Add-on Setup
 
  Terraform will deploy almost everything, but still a few components should be managed via UI. 

- **Confluent**: Terraform will enable Tableflow for topic: subscriber_perf_enriched and packetloss_result_anomaly_flatten with ICEBERG format. If tableflow is not in sync or in failed state, you shall resume it. 

- **AWS Quicksight**: Build your analytics to visualize the gold table and anomaly detection result

## <a name="step-6"></a>Build Quicksight Analytics
- Go to your Quicksight interface with selected region.

- Create analysis, select the dataset `demo.telco.packetloss_result_anomaly_flatten` that has been created in Terraform.
![step-1](images/step-1.png)

- Create a line chart for Anomaly Detection result:
    - `X axis: anomaly_ts`
    - `Value: actual_value, forecast_value, lower_bound, upper_bound`
![step-2](images/step-2.png)

- Explore more analytics by checking other gold tables (e.g. subscriber_perf_enriched):
![step-3](images/step-3.png)

> [!NOTE]
> It will take 15 minutes for the initial snapshot to be loaded into the dataset.

## <a name="step-7"></a>Cleanup
  ```bash
  terraform destroy 
  # Destroy again if any failures.
  ```
