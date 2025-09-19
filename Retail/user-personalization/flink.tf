resource "confluent_flink_compute_pool" "flink_compute_pool" {
  display_name = "${var.project_name}-flink-pool"
  cloud        = confluent_kafka_cluster.basic.cloud
  region       = var.kafka_cluster_region
  max_cfu      = var.flink_compute_pool_max_cfu
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  depends_on = [
    confluent_role_binding.custom_connect_statements_runner_environment_admin,
    confluent_role_binding.custom_connect_app_manager_assigner,
    confluent_role_binding.custom_connect_app_manager_flink_developer,
    confluent_role_binding.custom_connect_app_manager_transaction_id_developer_read,
    confluent_role_binding.custom_connect_app_manager_transaction_id_developer_write,
    confluent_api_key.custom_connect_app_manager_flink_api_key,
  ]
}


# 1. Create interaction_data table 
resource "confluent_flink_statement" "create_interaction_data" {
  organization {
    id = data.confluent_organization.my_org.id
  }

  environment {
    id = data.confluent_environment.existing_staging.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }

  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }

  statement = <<EOT
    CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS
      SELECT
  JSON_VALUE(JSON_UNQUOTE(document), '$.current_page_url.S') AS current_page_url,
  JSON_VALUE(JSON_UNQUOTE(document), '$.action_type.S')      AS action_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.item_id.S')          AS item_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.user_id.S')          AS user_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.browser_type.S')     AS browser_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.session_id.S')       AS session_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.device_type.S')      AS device_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.referrer_url.S')     AS referrer_url,
  TO_TIMESTAMP_LTZ(CAST(JSON_VALUE(JSON_UNQUOTE(document), '$.timestamp.S') AS BIGINT) * 1000, 3) AS event_time_ltz
FROM `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${aws_dynamodb_table.user_personalization.name}`;
  EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_connector.dynamodb_cdc_source
  ]
}

# 2. Add watermark to interaction_data 
resource "confluent_flink_statement" "alter_watermark_interaction_data" {
  organization {
    id = data.confluent_organization.my_org.id
  }

  environment {
    id = data.confluent_environment.existing_staging.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }

  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }

  statement = <<EOT
ALTER TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data`
MODIFY WATERMARK FOR event_time_ltz AS event_time_ltz;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_interaction_data
  ]
}

# 3. Insert data into interaction_data 
resource "confluent_flink_statement" "insert_interaction_data" {
  organization {
    id = data.confluent_organization.my_org.id
  }

  environment {
    id = data.confluent_environment.existing_staging.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }

  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }

  statement = <<EOT
    INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` 
      SELECT
  JSON_VALUE(JSON_UNQUOTE(document), '$.current_page_url.S') AS current_page_url,
  JSON_VALUE(JSON_UNQUOTE(document), '$.action_type.S')      AS action_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.item_id.S')          AS item_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.user_id.S')          AS user_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.browser_type.S')     AS browser_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.session_id.S')       AS session_id,
  JSON_VALUE(JSON_UNQUOTE(document), '$.device_type.S')      AS device_type,
  JSON_VALUE(JSON_UNQUOTE(document), '$.referrer_url.S')     AS referrer_url,
  TO_TIMESTAMP_LTZ(CAST(JSON_VALUE(JSON_UNQUOTE(document), '$.timestamp.S') AS BIGINT) * 1000, 3) AS event_time_ltz
FROM `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${aws_dynamodb_table.user_personalization.name}`;
  EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.alter_watermark_interaction_data
  ]
}

# 4. Create co_purchase_counts 
resource "confluent_flink_statement" "create_co_purchase_counts" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`co_purchase_counts`  AS
SELECT
  COALESCE(t1.item_id, 'unknown') AS item_id_A,
  COALESCE(t2.item_id, 'unknown') AS item_id_B,
  COUNT(*) AS co_purchase_count
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t1
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t2 ON t1.user_id = t2.user_id
WHERE
  t1.action_type = 'purchase' AND t2.action_type = 'purchase'
  AND t1.item_id <> t2.item_id
  AND t1.item_id IS NOT NULL AND t2.item_id IS NOT NULL
GROUP BY
  t1.item_id,
  t2.item_id;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.insert_interaction_data  # Wait for interaction_data to have data
  ]
}

# 5. Create user_purchase_totals 
resource "confluent_flink_statement" "create_user_purchase_totals" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`user_purchase_totals` AS
SELECT
  u.user_id,
  COALESCE(u.username, 'unknown') AS username,
  COALESCE(u.location, 'unknown') AS location,
  COALESCE(u.gender, 'unknown') AS gender,
  COUNT(i.action_type) FILTER (WHERE i.action_type = 'purchase') AS total_purchases
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.users` AS u
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS i ON u.user_id = CAST(i.user_id AS INT)
WHERE
  u.user_id IS NOT NULL
GROUP BY
  u.user_id,
  u.username,
  u.location,
  u.gender;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.insert_interaction_data,
    confluent_connector.postgre_sql_cdc_source
  ]
}

# 6. Create highly_rated_item_details 
resource "confluent_flink_statement" "create_highly_rated_item_details" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`highly_rated_item_details` AS
SELECT
  r.user_id,
  r.rating_score,
  r.item_id,
  i.image_url,
  i.brand_id,
  c.category_name
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.reviews` AS r
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.items` AS i ON r.item_id = i.item_id
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.categories` AS c ON i.category_id = c.category_id
WHERE
  r.rating_score >= 4
  AND i.availability_status = 'in_stock';
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_connector.postgre_sql_cdc_source
  ]
}

# 7. Create item_shared_by_user_pair 
resource "confluent_flink_statement" "create_item_shared_by_user_pair" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`item_shared_by_user_pair`  AS
SELECT
  COALESCE(t1.user_id, 'unknown') AS user_A,
  COALESCE(t2.user_id, 'unknown') AS user_B,
  COUNT(*) AS shared_item_count
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t1
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t2 ON t1.item_id = t2.item_id
WHERE
  t1.user_id <> t2.user_id
  AND t1.user_id IS NOT NULL AND t2.user_id IS NOT NULL
GROUP BY
  t1.user_id,
  t2.user_id;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.insert_interaction_data,
    confluent_connector.postgre_sql_cdc_source
  ]
}

# 8. Create purchase_windowed_counts 
resource "confluent_flink_statement" "create_purchase_windowed_counts" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
CREATE TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`purchase_windowed_counts` AS
SELECT
  user_id,
  item_id,
  window_start,
  window_end,
  COUNT(*) AS purchase_count
FROM TABLE(
  TUMBLE(
    TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data`,
    DESCRIPTOR(event_time_ltz),
    INTERVAL '30' MINUTES
  )
)
WHERE action_type = 'purchase'
GROUP BY user_id, item_id, window_start, window_end
HAVING COUNT(*) >= 2;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.alter_watermark_interaction_data,
    confluent_connector.postgre_sql_cdc_source
  ]
}

# 9-12. Insert statements for the remaining tables
resource "confluent_flink_statement" "insert_co_purchase_counts" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`co_purchase_counts`
SELECT
  COALESCE(t1.item_id, 'unknown') AS item_id_A,
  COALESCE(t2.item_id, 'unknown') AS item_id_B,
  COUNT(*) AS co_purchase_count
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t1
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t2 ON t1.user_id = t2.user_id
WHERE
  t1.action_type = 'purchase' AND t2.action_type = 'purchase'
  AND t1.item_id <> t2.item_id
  AND t1.item_id IS NOT NULL AND t2.item_id IS NOT NULL
GROUP BY
  t1.item_id,
  t2.item_id;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_co_purchase_counts
  ]
}

resource "confluent_flink_statement" "insert_user_purchase_totals" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`user_purchase_totals`
SELECT
  u.user_id,
  COALESCE(u.username, 'unknown') AS username,
  COALESCE(u.location, 'unknown') AS location,
  COALESCE(u.gender, 'unknown') AS gender,
  COUNT(i.action_type) FILTER (WHERE i.action_type = 'purchase') AS total_purchases
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.users` AS u
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS i ON u.user_id = CAST(i.user_id AS INT)
WHERE
  u.user_id IS NOT NULL
GROUP BY
  u.user_id,
  u.username,
  u.location,
  u.gender;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_user_purchase_totals
  ]
}

resource "confluent_flink_statement" "insert_highly_rated_item_details" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`highly_rated_item_details`
SELECT
  r.user_id,
  r.rating_score,
  r.item_id,
  i.image_url,
  i.brand_id,
  c.category_name
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.reviews` AS r
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.items` AS i ON r.item_id = i.item_id
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`${local.database_server_name}.user_data.categories` AS c ON i.category_id = c.category_id
WHERE
  r.rating_score >= 4
  AND i.availability_status = 'in_stock';
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_highly_rated_item_details
  ]
}

resource "confluent_flink_statement" "insert_item_shared_by_user_pair" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`item_shared_by_user_pair`
SELECT
  COALESCE(t1.user_id, 'unknown') AS user_A,
  COALESCE(t2.user_id, 'unknown') AS user_B,
  COUNT(*) AS shared_item_count
FROM
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t1
JOIN
  `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data` AS t2 ON t1.item_id = t2.item_id
WHERE
  t1.user_id <> t2.user_id
  AND t1.user_id IS NOT NULL AND t2.user_id IS NOT NULL
GROUP BY
  t1.user_id,
  t2.user_id;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_item_shared_by_user_pair
  ]
}

resource "confluent_flink_statement" "insert_purchase_windowed_counts" {
  organization {
    id = data.confluent_organization.my_org.id
  }
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flink_compute_pool.id
  }
  principal {
    id = confluent_service_account.custom_connect_statements_runner.id
  }
  statement = <<EOT
INSERT INTO `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`purchase_windowed_counts`
SELECT
  user_id,
  item_id,
  window_start,
  window_end,
  COUNT(*) AS purchase_count
FROM TABLE(
  TUMBLE(
    TABLE `${data.confluent_environment.existing_staging.display_name}`.`${confluent_kafka_cluster.basic.display_name}`.`interaction_data`,
    DESCRIPTOR(event_time_ltz),
    INTERVAL '30' MINUTES
  )
)
WHERE action_type = 'purchase'
GROUP BY user_id, item_id, window_start, window_end
HAVING COUNT(*) >= 2;
EOT

  properties = {
    "sql.current-catalog"  = confluent_kafka_cluster.basic.display_name
    "sql.current-database" = data.confluent_environment.existing_staging.display_name
  }

  rest_endpoint = data.confluent_flink_region.flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.custom_connect_app_manager_flink_api_key.id
    secret = confluent_api_key.custom_connect_app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_flink_statement.create_purchase_windowed_counts
  ]
}