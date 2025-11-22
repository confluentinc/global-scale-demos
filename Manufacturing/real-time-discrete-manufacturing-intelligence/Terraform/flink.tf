resource "confluent_flink_compute_pool" "pool" {
  display_name = var.flink_pool_name
  cloud        = var.cloud_provider
  region       = var.cloud_region
  max_cfu      = var.flink_max_cfu

  environment {
    id = data.confluent_environment.target.id
  }
}

resource "confluent_flink_statement" "stmt1" {
  organization { id = data.confluent_organization.org.id }
  environment  { id = data.confluent_environment.target.id }
  compute_pool { id = confluent_flink_compute_pool.pool.id }
  principal    { id = confluent_service_account.flink_sa.id }

  statement     = <<EOT
CREATE TABLE `${data.confluent_environment.target.display_name}`.`${confluent_kafka_cluster.main.display_name}`.`production_metrics_sink` (
    workorder_id STRING,
    product_category STRING,
    line_number STRING,
    routing_stage STRING,
    batch_number STRING,
    yield_percent DOUBLE,
    defect_rate DOUBLE,
    ok_count BIGINT,
    defect_count BIGINT,
    total_count BIGINT,
    avg_temperature DOUBLE,
    avg_pressure DOUBLE,
    last_updated TIMESTAMP(3),
    PRIMARY KEY (workorder_id, product_category, line_number, routing_stage, batch_number) NOT ENFORCED
)
DISTRIBUTED INTO 1 BUCKETS
WITH ('connector' = 'confluent');
EOT
  properties    = {
    "sql.current-catalog"  = data.confluent_environment.target.display_name
    "sql.current-database" = confluent_kafka_cluster.main.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.flink_api.id
    secret = confluent_api_key.flink_api.secret
  }

  depends_on = [
    confluent_kafka_cluster.main,
    confluent_flink_compute_pool.pool,
    confluent_api_key.flink_api,
    confluent_role_binding.flink_sa_developer,
    confluent_kafka_acl.flink_describe_cluster,
    confluent_kafka_acl.flink_sink_topic_create,
    confluent_kafka_acl.flink_sink_topic_write,
    confluent_kafka_topic.sensor_events,
    confluent_kafka_topic.work_orders,
    confluent_role_binding.flink_sa_flink_admin,
    confluent_role_binding.flink_assigner,
  ]
}

# Statement 2
resource "confluent_flink_statement" "stmt2" {
  organization { id = data.confluent_organization.org.id }
  environment  { id = data.confluent_environment.target.id }
  compute_pool { id = confluent_flink_compute_pool.pool.id }
  principal    { id = confluent_service_account.flink_sa.id }

  statement     = <<EOT
INSERT INTO `${data.confluent_environment.target.display_name}`.`${confluent_kafka_cluster.main.display_name}`.`production_metrics_sink`
SELECT
    s.workorder_id,
    w.product_category,
    s.line_number,
    s.routing_stage,
    s.batch_number,
    (CAST(SUM(CASE WHEN s.is_defective = false THEN 1 ELSE 0 END) AS DOUBLE) * 100.0 / COUNT(*)) AS yield_percent,
    (CAST(SUM(CASE WHEN s.is_defective = true THEN 1 ELSE 0 END) AS DOUBLE) * 100.0 / COUNT(*)) AS defect_rate,
    SUM(CASE WHEN s.is_defective = false THEN 1 ELSE 0 END) AS ok_count,
    SUM(CASE WHEN s.is_defective = true THEN 1 ELSE 0 END) AS defect_count,
    COUNT(*) AS total_count,
    AVG(s.temperature) AS avg_temperature,
    AVG(s.pressure) AS avg_pressure,
    CURRENT_TIMESTAMP AS last_updated
FROM `mf.public.sensor_events` s
JOIN `mf.public.work_orders` w
  ON s.workorder_id = w.workorder_id
GROUP BY
    s.workorder_id,
    w.product_category,
    s.line_number,
    s.routing_stage,
    s.batch_number;
EOT
  properties    = {
    "sql.current-catalog"  = data.confluent_environment.target.display_name
    "sql.current-database" = confluent_kafka_cluster.main.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.flink_api.id
    secret = confluent_api_key.flink_api.secret
  }

  depends_on = [
    confluent_flink_statement.stmt1,
    confluent_role_binding.flink_sa_developer,
    confluent_role_binding.flink_sa_flink_admin,
    confluent_role_binding.flink_assigner,
    confluent_api_key.flink_api
  ]
}

# Statement 3
resource "confluent_flink_statement" "stmt3" {
  organization { id = data.confluent_organization.org.id }
  environment  { id = data.confluent_environment.target.id }
  compute_pool { id = confluent_flink_compute_pool.pool.id }
  principal    { id = confluent_service_account.flink_sa.id }

  statement     = <<EOT
CREATE TABLE `${data.confluent_environment.target.display_name}`.`${confluent_kafka_cluster.main.display_name}`.`production_metrics_history` (
    workorder_id STRING,
    product_category STRING,
    line_number STRING,
    routing_stage STRING,
    yield_percent DOUBLE,
    defect_rate DOUBLE,
    ok_count BIGINT,
    defect_count BIGINT,
    total_count BIGINT,
    temperature DOUBLE,
    pressure DOUBLE,
    defect_reason STRING,
    item_id STRING,
    event_ts TIMESTAMP_LTZ(3)
)
DISTRIBUTED INTO 1 BUCKETS
WITH ('connector' = 'confluent');
EOT
  properties    = {
    "sql.current-catalog"  = data.confluent_environment.target.display_name
    "sql.current-database" = confluent_kafka_cluster.main.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.flink_api.id
    secret = confluent_api_key.flink_api.secret
  }

  depends_on = [
    confluent_flink_statement.stmt2,
    confluent_role_binding.flink_sa_developer,
    confluent_role_binding.flink_sa_flink_admin,
    confluent_role_binding.flink_assigner,
    confluent_api_key.flink_api
  ]
}

# Statement 4
resource "confluent_flink_statement" "stmt4" {
  organization { id = data.confluent_organization.org.id }
  environment { id = data.confluent_environment.target.id }
  compute_pool { id = confluent_flink_compute_pool.pool.id }
  principal { id = confluent_service_account.flink_sa.id }

  statement     = <<EOT
INSERT INTO `${data.confluent_environment.target.display_name}`.`${confluent_kafka_cluster.main.display_name}`.`production_metrics_history`
SELECT
    s.workorder_id,
    w.product_category,
    s.line_number,
    s.routing_stage,
    CAST(s.ok_count * 100.0 / s.total_count AS DOUBLE)    AS yield_percent,
    CAST(s.defect_count * 100.0 / s.total_count AS DOUBLE) AS defect_rate,
    CAST(s.ok_count AS BIGINT)                             AS ok_count,
    CAST(s.defect_count AS BIGINT)                         AS defect_count,
    CAST(s.total_count AS BIGINT)                          AS total_count,
    s.temperature                                          AS temperature,
    s.pressure                                             AS pressure,
    s.defect_reason                                        AS defect_reason,
    s.item_id,
    s.rowtime                                              AS event_ts
FROM (
    SELECT
        workorder_id,
        item_id,
        line_number,
        routing_stage,
        temperature,
        pressure,
        defect_reason,
        $rowtime AS rowtime,
        SUM(CASE WHEN is_defective = false THEN 1 ELSE 0 END) OVER w AS ok_count,
        SUM(CASE WHEN is_defective = true THEN 1 ELSE 0 END) OVER w AS defect_count,
        COUNT(*) OVER w                                         AS total_count
    FROM `mf.public.sensor_events`
    WINDOW w AS (
        PARTITION BY workorder_id, line_number
        ORDER BY $rowtime
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
) AS s
JOIN `mf.public.work_orders` AS w
  ON s.workorder_id = w.workorder_id;
EOT
  properties    = {
    "sql.current-catalog"  = data.confluent_environment.target.display_name
    "sql.current-database" = confluent_kafka_cluster.main.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.flink_api.id
    secret = confluent_api_key.flink_api.secret
  }

  depends_on = [
    confluent_flink_statement.stmt3,
    confluent_role_binding.flink_sa_developer,
    confluent_role_binding.flink_sa_flink_admin,
    confluent_role_binding.flink_assigner,
    confluent_api_key.flink_api
  ]

}