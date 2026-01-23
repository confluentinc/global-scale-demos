# Steps to run this file
# python3 -m venv path/to/venv
# source path/to/venv/bin/activate
# pip install dash pandas plotly psycopg2-binary
# python3 shopfloor_dashboard.py

import dash
from dash import dcc, html, Input, Output
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import psycopg2
from datetime import datetime
import numpy as np
from dotenv import load_dotenv
import os

# -----------------------------
# Configuration
# -----------------------------
DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": 5432,
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD")
}

TEMP_WARNING_THRESHOLD = 110 # For the Red Alert KPI
TEMP_CRITICAL_THRESHOLD = 125 # For Advanced Notification

# Define fixed order for routing stages for the bar chart
ROUTING_STAGE_ORDER = [
    "Material Receipt", "Pre-Processing", "Fabrication",
    "Assembly", "Quality Inspection", "Packing"
]

# Define custom pastel colors for stages
# Mapped to the ROUTING_STAGE_ORDER for consistency
PASTEL_STAGE_COLORS = {
    "Material Receipt": "#0A3D62",  # Pastel Blue
    "Pre-Processing": "#1B5E8C",    # Mint Green
    "Fabrication": "#327DB1",       # Soft Pink
    "Assembly": "#5AA4D6",          # Light Peach
    "Quality Inspection": "#8BC4EB", # Lavender
    "Packing": "#C6E4F8"            # Aqua Pastel
}

# -----------------------------
# Helper: Read Latest Data
# -----------------------------
def get_data():
    conn = psycopg2.connect(**DB_CONFIG)
    # Ensure item_id is fetched for unique counting and Red Alert
    query = """
        SELECT
            event_ts AS ts,
            workorder_id,
            product_category,
            line_number,
            routing_stage,
            temperature,
            pressure,
            yield_percent,
            defect_rate,
            ok_count,
            defect_count,
            total_count,
            defect_reason,
            item_id
        FROM production_metrics_history
        ORDER BY ts DESC LIMIT 5000;
    """
    try:
        df = pd.read_sql(query, conn)
    except Exception as e:
        print(f"Error reading from DB: {e}")
        df = pd.DataFrame()
    finally:
        conn.close()

    if not df.empty:
        df['ts'] = pd.to_datetime(df['ts'])
        df = df.sort_values('ts')
    return df

# -----------------------------
# App UI
# -----------------------------
app = dash.Dash(__name__)
app.title = "Shopfloor Intelligence Dashboard"

app.layout = html.Div([
    html.H1("🏭 Real-Time Discrete Manufacturing Intelligence",
            style={'textAlign': 'center', 'marginBottom': '20px', 'fontFamily': 'Arial', 'color': '#333'}),

    # --- Filter Section (TOP ROW - REMAINS AS IS) ---
    html.Div([
        html.Div([
            html.Label("Filter by Line:", style={'fontWeight': 'bold'}),
            dcc.Dropdown(id='line-filter', multi=True, placeholder="All Lines")
        ], style={'flex': '1', 'marginRight': '10px'}),

        html.Div([
            html.Label("Filter by Stage:", style={'fontWeight': 'bold'}),
            dcc.Dropdown(id='stage-filter', multi=True, placeholder="All Stages")
        ], style={'flex': '1', 'marginRight': '10px'}),

        html.Div([
            html.Label("Work Order:", style={'fontWeight': 'bold'}),
            dcc.Dropdown(id='wo-filter', multi=True, placeholder="All Workorders")
        ], style={'flex': '1'}),
    ], style={'display': 'flex', 'width': '95%', 'margin': 'auto', 'marginBottom': '20px', 'backgroundColor': '#f9f9f9', 'padding': '15px', 'borderRadius': '5px'}),

    # --- KPI Cards Row 1 (Overall Metrics - RE-ADDED TOTAL ITEMS) ---
    html.Div(id='kpi-cards', style={'display': 'flex', 'justifyContent': 'space-around', 'marginBottom': '20px'}),

    # --- KPI Cards Row 2 (Line-specific Avg Temp - REMAINS AS IS) ---
    html.H3("Average Temperature per Assembly Line (Operational View)", style={'textAlign': 'left', 'width': '95%', 'margin': 'auto', 'marginTop': '20px', 'marginBottom': '10px'}),
    html.Div(id='avg-temp-line-cards', style={'display': 'flex', 'flexWrap': 'wrap', 'justifyContent': 'left', 'width': '95%', 'margin': 'auto', 'marginBottom': '20px'}),

    # --- CHARTS ROW 1 (Real Time Trend: Yield - FULL WIDTH) ---
    html.Div([
        html.Div([
            html.H3("Real-Time Yield Trend", style={'textAlign': 'center'}),
            dcc.Graph(id='yield-trend')
        ], style={'width': '100%'}) # Use 100% for full width
    ], style={'width': '95%', 'margin': 'auto', 'marginBottom': '20px'}),

    # --- CHARTS ROW 2 (Temperature & Pressure Trends - TWO COLUMNS) ---
    html.Div([
        # Temperature Trend (Column 1)
        html.Div([dcc.Graph(id='temp-trend')], style={'width': '49%', 'display': 'inline-block', 'verticalAlign': 'top'}),
        # Pressure Trend (Column 2)
        html.Div([dcc.Graph(id='pressure-trend')], style={'width': '49%', 'display': 'inline-block', 'float':'right', 'verticalAlign': 'top'})
    ], style={'width': '95%', 'margin': 'auto', 'marginBottom': '20px'}),

    # --- CHARTS ROW 3 (Stage Rejections & Defect Pie - TWO COLUMNS) ---
    html.Div([
        # Rejection by Stage (Column 1)
        html.Div([dcc.Graph(id='reject-by-stage')], style={'width': '49%', 'display': 'inline-block', 'verticalAlign': 'top'}),
        # Defect Pie (Column 2)
        html.Div([dcc.Graph(id='defect-pie')], style={'width': '49%', 'display': 'inline-block', 'float':'right', 'verticalAlign': 'top'})
    ], style={'width': '95%', 'margin': 'auto', 'marginBottom': '20px'}),

    dcc.Interval(id='interval-component', interval=15*1000, n_intervals=0)
])

# -----------------------------
# Callbacks for Filters (UNCHANGED)
# -----------------------------
@app.callback(
    [Output('line-filter', 'options'), Output('stage-filter', 'options'), Output('wo-filter', 'options')],
    [Input('interval-component', 'n_intervals')]
)
def update_filter_options(n):
    df = get_data()
    if df.empty: return [], [], []
    return (
        [{'label': i, 'value': i} for i in sorted(df['line_number'].dropna().unique())],
        [{'label': i, 'value': i} for i in sorted(df['routing_stage'].dropna().unique())],
        [{'label': i, 'value': i} for i in sorted(df['workorder_id'].dropna().unique())]
    )

# -----------------------------
# Callbacks for Dashboard Content (UPDATED KPI CARDS)
# -----------------------------
@app.callback(
    [Output('kpi-cards', 'children'),
     Output('avg-temp-line-cards', 'children'),
     Output('yield-trend', 'figure'),
     Output('reject-by-stage', 'figure'),
     Output('defect-pie', 'figure'),
     Output('temp-trend', 'figure'),
     Output('pressure-trend', 'figure')],
    [Input('interval-component', 'n_intervals'),
     Input('line-filter', 'value'),
     Input('stage-filter', 'value'),
     Input('wo-filter', 'value')]
)
def update_dashboard(n, lines, stages, wos):
    df = get_data()

    # Adjusted width to 16% to accommodate 6 KPI cards in one row
    kpi_style = {'border': '1px solid #ddd', 'padding': '15px', 'width': '16%', 'textAlign': 'center', 'borderRadius': '8px', 'boxShadow': '2px 2px 5px rgba(0,0,0,0.1)', 'marginRight': '10px'}

    if df.empty:
        empty_kpi = [html.Div("Waiting for data stream...", style=kpi_style)]
        return empty_kpi, [], {}, {}, {}, {}, {}

    # --- Filtering ---
    df_filtered = df.copy()
    if lines: df_filtered = df_filtered[df_filtered['line_number'].isin(lines)]
    if stages: df_filtered = df_filtered[df_filtered['routing_stage'].isin(stages)]
    if wos: df_filtered = df_filtered[df_filtered['workorder_id'].isin(wos)]

    if df_filtered.empty:
        empty_kpi = [html.Div("No data for selected filters", style=kpi_style)]
        return empty_kpi, [], {}, {}, {}, {}, {}

    # --- KPI Calculations ---
    # Current Yield/Defect Rate: Use the last reported value after filtering
    latest_row = df_filtered.iloc[-1]
    avg_yield = latest_row['yield_percent'] if not pd.isna(latest_row['yield_percent']) else 0
    avg_defect_rate = latest_row['defect_rate'] if not pd.isna(latest_row['defect_rate']) else 0

    # Overall Metrics
    total_items = df_filtered['item_id'].nunique() # Re-using this calculated variable
    overall_avg_temp = df_filtered['temperature'].mean()

    # Temp > 110°C Alerts (Warning)
    warning_alert_count = df_filtered[df_filtered['temperature'] > TEMP_WARNING_THRESHOLD]['item_id'].nunique()

    # Advanced Notification (Critical)
    critical_lines = df_filtered[df_filtered['temperature'] > TEMP_CRITICAL_THRESHOLD]['line_number'].unique()
    critical_lines_str = ', '.join(critical_lines) if critical_lines.size > 0 else 'None'
    critical_lines_color = 'red' if critical_lines.size > 0 else 'green'


    # --- KPI Cards Display (Now 6 cards) ---
    kpi_cards = [
        # RE-ADDED: Total Items Tracked
        html.Div([html.H4("Total Items Tracked"), html.H2(f"{total_items}", style={'color': '#1E90FF'})], style=kpi_style),

        # Existing KPIs
        html.Div([html.H4("Current Yield"), html.H2(f"{avg_yield:.1f}%", style={'color': 'green'})], style=kpi_style),
        html.Div([html.H4("Defect Rate"), html.H2(f"{avg_defect_rate:.1f}%", style={'color': 'red'})], style=kpi_style),
        html.Div([html.H4("Avg Temp (Overall)"), html.H2(f"{overall_avg_temp:.1f}°C", style={'color': 'orange'})], style=kpi_style),
        html.Div([html.H4(f"Warning Temp ({TEMP_WARNING_THRESHOLD}°C)"), html.H2(f"{warning_alert_count}", style={'color': 'red'})], style=kpi_style),
        html.Div([html.H4(f"Critical Line(s) > {TEMP_CRITICAL_THRESHOLD}°C"), html.H5(critical_lines_str, style={'color': critical_lines_color, 'overflowWrap': 'break-word', 'fontSize': '1.0em', 'padding': '2px'})], style=kpi_style),
    ]

    # --- KPI Cards per Line ---
    avg_temp_by_line = df_filtered.groupby('line_number')['temperature'].mean().round(1).reset_index()
    line_kpi_cards = []
    line_kpi_style = {'border': '1px solid #ddd', 'padding': '10px', 'width': '15%', 'textAlign': 'center', 'borderRadius': '5px', 'boxShadow': '1px 1px 3px rgba(0,0,0,0.05)', 'marginRight': '10px', 'marginBottom': '10px'}

    for index, row in avg_temp_by_line.iterrows():
        if row['temperature'] > TEMP_CRITICAL_THRESHOLD:
            temp_color = 'red'
        elif row['temperature'] > TEMP_WARNING_THRESHOLD:
            temp_color = 'orange'
        else:
            temp_color = 'green'

        line_kpi_cards.append(
            html.Div([
                html.H5(f"Line: {row['line_number']}"),
                html.H4(f"{row['temperature']}°C", style={'color': temp_color})
            ], style=line_kpi_style)
        )

    # --- Charts ---

    # 1. Yield Trend (Stabilized & Y-Axis fixed 0-100)
    df_filtered_yield = df_filtered[df_filtered['total_count'] > 50]
    yield_fig = px.line(df_filtered_yield, x='ts', y='yield_percent', color='line_number',
                        title="Real-Time Yield by Assembly Line (Stabilized Trend)",
                        labels={'ts': 'Time', 'yield_percent': 'Yield %', 'line_number': 'Line'})
    yield_fig.update_yaxes(range=[0, 100])

    # 2. Rejection by Stage (Fixed Order & Custom Pastel Colors)
    stage_rejection_data = df_filtered[df_filtered['defect_reason'].notnull()]
    stage_rejection_count = stage_rejection_data.groupby('routing_stage')['item_id'].nunique().reset_index()
    stage_rejection_count.columns = ['Stage', 'Rejected_Items']

    # Sort the data frame by the fixed order before plotting
    stage_rejection_count['Stage'] = pd.Categorical(
        stage_rejection_count['Stage'],
        categories=ROUTING_STAGE_ORDER,
        ordered=True
    )
    stage_rejection_count = stage_rejection_count.sort_values('Stage')

    # Create the bar chart using the custom discrete color map
    reject_by_stage_fig = px.bar(
        stage_rejection_count,
        x='Stage',
        y='Rejected_Items',
        title="Rejected Items Count by Routing Stage (Sequential)",
        color='Stage', # Color by Stage name to use the discrete map
        color_discrete_map=PASTEL_STAGE_COLORS, # Use the hardcoded hex colors
        category_orders={"Stage": ROUTING_STAGE_ORDER}
    )

    # 3. Defect Reason Pie Chart
    defect_data = df_filtered[df_filtered['defect_reason'].notnull()]
    if not defect_data.empty:
        reason_count = defect_data.groupby('defect_reason')['item_id'].nunique().reset_index()
        reason_count.columns = ['Reason', 'Count']
        defect_pie_fig = px.pie(reason_count, values='Count', names='Reason',
                                title="Defect Root Cause Distribution",
                                hole=.3)
    else:
        defect_pie_fig = px.pie(title="No Defects Reported")

    # 4. Temperature Trend (Line Chart)
    temp_fig = px.line(df_filtered, x='ts', y='temperature', color='line_number',
                       title="Temperature Telemetry (Line Trend)",
                       labels={'ts': 'Time', 'temperature': 'Temperature (°C)'})
    temp_fig.add_hline(y=TEMP_WARNING_THRESHOLD, line_dash="dash", annotation_text=f"Warning ({TEMP_WARNING_THRESHOLD}°C)", annotation_position="top left", line_color="orange")
    temp_fig.add_hline(y=TEMP_CRITICAL_THRESHOLD, line_dash="dot", annotation_text=f"Critical ({TEMP_CRITICAL_THRESHOLD}°C)", annotation_position="top left", line_color="red")

    # 5. Pressure Trend (Line Chart)
    pressure_fig = px.line(df_filtered, x='ts', y='pressure', color='line_number',
                           title="Pressure Telemetry (Line Trend)",
                           labels={'ts': 'Time', 'pressure': 'Pressure (psi)'})
    pressure_fig.add_hline(y=160, line_dash="dot", annotation_text="Max Pressure", line_color="red")
    pressure_fig.add_hline(y=80, line_dash="dot", annotation_text="Min Pressure", line_color="red")

    # Update layout for clean look
    for fig in [yield_fig, reject_by_stage_fig, defect_pie_fig, temp_fig, pressure_fig]:
        fig.update_layout(margin=dict(l=20, r=20, t=40, b=20), legend_title_text="")

    return kpi_cards, line_kpi_cards, yield_fig, reject_by_stage_fig, defect_pie_fig, temp_fig, pressure_fig

if __name__ == "__main__":
    print("[INFO] Starting Shopfloor Dashboard at http://127.0.0.1:8050")
    app.run(host="0.0.0.0",debug=True)