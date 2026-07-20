CREATE TABLE metro_station_anomaly_scores
DISTRIBUTED INTO 1 BUCKETS
AS
SELECT
    metro_line,
    direction,
    current_station,
    agg_window_end,
    total_headcount,
    active_trains,
    anomaly_results[6] AS is_anomaly
FROM (
    SELECT
        metro_line,
        direction,
        current_station,
        agg_window_end,
        total_headcount,
        active_trains,
        ML_DETECT_ANOMALIES(
            CAST(total_headcount AS DOUBLE),
            $rowtime,
            JSON_OBJECT('minTrainingSize' VALUE 5, 'confidencePercentage' VALUE 90.0)
        ) OVER (
            PARTITION BY metro_line, direction, current_station
            ORDER BY $rowtime
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS anomaly_results
    FROM metro_station_headcounts
);
