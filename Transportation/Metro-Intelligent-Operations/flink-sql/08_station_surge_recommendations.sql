CREATE TABLE metro_station_surge_recommendations
DISTRIBUTED INTO 1 BUCKETS
WITH ('value.format' = 'json-registry')
AS
SELECT
    a.metro_line,
    a.direction,
    a.current_station,
    a.agg_window_end,
    a.total_headcount,
    a.baseline_avg,
    a.active_trains,
    a.arima_flagged,
    p.recommendation
FROM metro_station_surge_anomalies AS a,
LATERAL TABLE(
    ML_PREDICT(
        'metro_surge_advisor',
        CONCAT(
            'Metro ', a.metro_line, ' line, ', a.direction, ' direction, at ', a.current_station, ' station: ',
            CAST(a.total_headcount AS STRING), ' passengers counted in the last 5-minute window, ',
            'at least 2x the recent normal baseline of ', CAST(CAST(a.baseline_avg AS DECIMAL(10, 1)) AS STRING), ', ',
            'with ', CAST(a.active_trains AS STRING), ' trains currently active on this line and direction. ',
            'A new train cannot realistically be inserted into service within minutes, so do not suggest that. ',
            'Write a short control-room alert in at most three sentences: (1) one plausible real-world cause for ',
            'a sudden crowd surge at this specific station (for example a large public event nearby letting out, ',
            'a service disruption on a connecting line, or a public holiday), stated as a possibility rather than ',
            'a fact, (2) the severity of this surge, and (3) one realistic immediate action (for example extra ',
            'platform staff, crowd control barriers, passenger announcements, or prioritizing the next scheduled ',
            'train on this line).'
        )
    )
) AS p (recommendation);
