// Builds the n8n credentials file from environment variables that Kubernetes
// injects from Secrets. n8n encrypts the values with N8N_ENCRYPTION_KEY when
// they are imported, so plain-text keys only ever exist in memory and in a
// private temp file that bootstrap.sh deletes straight away.
const required = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`missing required environment variable ${name}`);
    process.exit(1);
  }
  return value;
};

// IDs match the references inside workflows/*.json.
const credentials = [
  {
    id: 'echoLlmApi000001',
    name: 'EchoMind LLM',
    type: 'openAiApi',
    data: { apiKey: required('LLM_API_KEY'), url: required('LLM_BASE_URL') },
  },
  {
    id: 'jmVN7xYccnea37Bw',
    name: 'Hugging Face account',
    type: 'huggingFaceApi',
    data: { apiKey: required('HUGGINGFACE_API_KEY') },
  },
  {
    id: 'echoMemoryDb0001',
    name: 'EchoMind memory database',
    type: 'postgres',
    data: {
      host: required('ECHOMIND_DB_HOST'),
      port: Number(process.env.ECHOMIND_DB_PORT || 5432),
      database: required('ECHOMIND_DB_NAME'),
      user: required('ECHOMIND_DB_USER'),
      password: required('ECHOMIND_DB_PASSWORD'),
      ssl: 'disable',
    },
  },
  {
    id: 'echoIngestAuth01',
    name: 'EchoMind ingest token',
    type: 'httpHeaderAuth',
    data: { name: 'X-EchoMind-Token', value: required('ECHOMIND_INGEST_TOKEN') },
  },
  {
    id: 'echoRecallAuth01',
    name: 'EchoMind recall login',
    type: 'httpBasicAuth',
    data: { user: 'echomind', password: required('ECHOMIND_RECALL_PASSWORD') },
  },
];

process.stdout.write(JSON.stringify(credentials));
