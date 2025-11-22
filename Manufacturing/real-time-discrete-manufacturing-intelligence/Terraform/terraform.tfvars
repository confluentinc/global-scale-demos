cloud_provider     = "AWS"
cloud_region       = "ap-south-1"

postgres_port     = 5432
postgres_user     = "postgres"
postgres_password = "postgres"
postgres_db_name  = "postgres"
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

