## Running Terraform Scripts

Before you can run this Terraform section, ensure you have the following software:

1. A user account on Confluent Cloud
2. Local install of Terraform
3. Local install of the Confluent CLI
4. Create an API Key using Confluent CLI:

```bash
confluent login
confluent api-key create --resource cloud --description "API for terraform"
```

It may take a couple of minutes for the API key to be ready. Save the API key and secret. The secret is not retrievable later.

```bash
API Key    | <yourkey>
```
```bash                                         
API Secret | <yoursecret>
```
```bash                                     
cat > terraform.tfvars <<EOF
confluent_cloud_api_key = "{Cloud API Key}"
confluent_cloud_api_secret = "{Cloud API Key Secret}"
use_prefix = "{Your Name}"
EOF
```

Run the following commands to provision the environment

```bash
terraform init
```
```bash
terraform plan
```
```bash
terraform apply
```

After completing the tasks, please remove your environment to avoid costs. You can recreate it anytime, using the steps above

```bash
terraform destroy
```

##  Deploying a Flink statement in Terraform example

Please refer to the below example to run a flink sql statement in terraform 

Example : 

```bash
# Deploy a Flink SQL statement to Confluent Cloud.
resource "confluent_flink_statement" "my_flink_statement" {
  organization {
    id = data.confluent_organization.my_org.id
  }

  environment {
    id = confluent_environment.my_env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.my_compute_pool.id
  }

  principal {
    id = confluent_service_account.my_service_account.id
  }

  # This SQL reads data from source_topic, filters it, and ingests the filtered data into sink_topic.
  statement = <<EOT
    CREATE TABLE my_sink_topic AS
    SELECT
      window_start,
      window_end,
      SUM(price) AS total_revenue,
      COUNT(*) AS cnt
    FROM
    TABLE(TUMBLE(TABLE `examples`.`marketplace`.`orders`, DESCRIPTOR($rowtime), INTERVAL '1' MINUTE))
    GROUP BY window_start, window_end;
    EOT

  properties = {
    "sql.current-catalog"  = confluent_environment.my_env.display_name
    "sql.current-database" = confluent_kafka_cluster.my_kafka_cluster.display_name
  }

  rest_endpoint = data.confluent_flink_region.my_flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.my_flink_api_key.id
    secret = confluent_api_key.my_flink_api_key.secret
  }

  depends_on = [
    confluent_api_key.my_flink_api_key,
    confluent_flink_compute_pool.my_compute_pool,
    confluent_kafka_cluster.my_kafka_cluster
  ]
}
```


