CREATE TABLE metro_station_surge_anomalies
DISTRIBUTED INTO 1 BUCKETS
WITH ('value.format' = 'json-registry')
AS
SELECT
    metro_line,
    direction,
    current_station,
    agg_window_end,
    total_headcount,
    active_trains,
    baseline_avg,
    is_anomaly AS arima_flagged
FROM (
    SELECT
        metro_line,
        direction,
        current_station,
        agg_window_end,
        total_headcount,
        active_trains,
        is_anomaly,
        CASE
            WHEN window_count > 1 THEN (window_sum - total_headcount) / (window_count - 1)
            ELSE CAST(NULL AS DOUBLE)
        END AS baseline_avg
    FROM (
        SELECT
            metro_line,
            direction,
            current_station,
            agg_window_end,
            total_headcount,
            active_trains,
            is_anomaly,
            CAST(SUM(total_headcount) OVER (
                PARTITION BY metro_line, direction, current_station
                ORDER BY $rowtime
                ROWS BETWEEN 12 PRECEDING AND CURRENT ROW
            ) AS DOUBLE) AS window_sum,
            COUNT(*) OVER (
                PARTITION BY metro_line, direction, current_station
                ORDER BY $rowtime
                ROWS BETWEEN 12 PRECEDING AND CURRENT ROW
            ) AS window_count
        FROM metro_station_anomaly_scores
    )
)
WHERE baseline_avg IS NOT NULL
  AND total_headcount >= baseline_avg * 2.0;
