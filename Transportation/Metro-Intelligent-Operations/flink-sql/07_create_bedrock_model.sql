CREATE MODEL `metro_surge_advisor`
INPUT (prompt STRING)
OUTPUT (recommendation STRING)
WITH (
    'provider' = 'bedrock',
    'task' = 'text_generation',
    'bedrock.connection' = 'metro-bedrock-connection',
    'bedrock.params.max_tokens' = '300'
);
