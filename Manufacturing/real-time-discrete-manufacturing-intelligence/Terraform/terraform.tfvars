confluent_cloud_api_key    = "<USER INPUT>"
confluent_cloud_api_secret = "<USER INPUT>"
environment_id             = "<USER INPUT>"
environment_name           = "<USER INPUT>"

name_prefix        = "mf"
kafka_cluster_name = "smf-cluster"
cloud_provider     = "<USER INPUT>"
cloud_region       = "<USER INPUT>"

postgres_host     = "<USER INPUT>"
postgres_port     = 5432
postgres_user     = "<USER INPUT>"
postgres_password = "<USER INPUT>"
postgres_db_name  = "<USER INPUT>"
postgres_sslmode  = "prefer"

cdc_topic_prefix        = "mf"
cdc_output_value_format = "AVRO"
cdc_output_key_format   = "AVRO"
cdc_table_include_list = "public.sensor_events,public.work_orders"

sink_insert_topics       = "production_metrics_history"
sink_insert_value_format = "AVRO"
sink_insert_key_format   = "AVRO"

sink_upsert_topics       = "production_metrics_sink"
sink_upsert_value_format = "AVRO"
sink_upsert_key_format   = "AVRO"
sink_upsert_pk_mode      = "record_key"
sink_upsert_pk_fields    = "workorder_id,product_category"
flink_pool_name = "smf-flink-pool"
flink_max_cfu   = 5

