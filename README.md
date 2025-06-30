# AWS Serverless Review Analysis Pipeline

An event-driven serverless application for analyzing customer reviews using AWS Lambda, S3, and DynamoDB. The application performs profanity checks and sentiment analysis, automatically banning users who use excessive profanity.

## 🎯 Features

- **Text Preprocessing**: Tokenization, stop word removal, lemmatization
- **Profanity Check**: Detection and counting of profane words
- **Sentiment Analysis**: Classification as positive/negative/neutral
- **Automatic Banning**: Users are banned after >3 reviews containing profanity
- **Complete Pipeline**: S3 → Lambda → S3 → Lambda → ... → DynamoDB

## 📋 Prerequisites

- Docker & Docker Compose
- Git
- Linux/Mac/Windows with WSL2

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/felixkapfer/194048_dic_sose2025_a3.git
cd https://github.com/felixkapfer/194048_dic_sose2025_a3.git
```

### 2. Start Infrastructure
```bash
./main.sh start
```
Wait until you see "Containers are running".
Start the infrastructure
Connect to docker container using option 4

### 3. Connect to Container
select option to connect

### 4. Set Up AWS Resources (inside container)

Execute options **in this exact order**:

1. **Option 2**: Create S3 & DynamoDB
2. **Option 3**: Set SSM Parameters
3. **Option 4**: Prepare Lambda ZIP Files
4. **Option 5**: Deploy Lambda Functions
5. **Option 6**: Set Lambda Permissions
6. **Option 7**: Set S3 Notifications ⚠️ **IMPORTANT: BEFORE uploading!**
7. **Option 8**: Start Pipeline (upload reviews)
8. **Option 9**: Show Results

**Alternative**: Option 11 runs all steps automatically.

## 📁 Project Structure

```
.
├── docker-compose.yaml      # Container configuration
├── Dockerfile              # Docker image definition
├── main.sh                 # Host system management
├── requirements.txt        # Python dependencies
├── data/
│   └── reviews_devset.json # Test dataset
├── scripts/
│   ├── app.sh             # Container menu
│   ├── workflows.sh       # AWS operations
│   └── ...                # Additional scripts
└── src/
    └── lambdas/
        ├── preprocessing_lambda.py  # Text preprocessing
        ├── profanity_lambda.py     # Profanity detection
        ├── sentiment_lambda.py     # Sentiment analysis
        └── ddb_lambda.py          # DynamoDB storage
```

## 🔄 Pipeline Flow

```
1. Review → S3 (raw/)
       ↓
2. preprocessing_lambda → S3 (preprocessed/)
       ↓
3. profanity_lambda → S3 (profanity/)
       ↓
4. sentiment_lambda → S3 (sentiment/)
       ↓
5. ddb_lambda → DynamoDB (aggregation & ban check)
```

## 📊 Results

After pipeline completion, you'll find in DynamoDB:
- Number of reviews per user
- Number of reviews containing profanity
- Sentiment distribution (positive/negative/neutral)
- Ban status (true/false for >3 profanity reviews)
- List of all profane words used

## 🐛 Troubleshooting

### "Lambda ZIP file not found"
```bash
# Run inside container:
apt-get update && apt-get install -y zip
# Then run Option 4 again
```

### "notification-config.json not found"
```bash
cp /app/src/lambdas/notification-config.json /app/scripts/
```

### DynamoDB remains empty
- Ensure S3 Notifications were set BEFORE upload
- Upload a new test review:
```bash
cd /app/data
head -1 reviews_devset.json > test.json
aws --endpoint-url=http://localstack:4566 --region us-east-1 s3 cp test.json s3://reviews-bucket/raw/test_new.json
```

### Rebuild container (after Dockerfile changes)
```bash
./main.sh stop
docker-compose build --no-cache app
./main.sh start
```


### Upload Specific Number of Reviews
```bash
python /app/scripts/upload_reviews_to_s3.py /app/data/reviews_devset.json 100
```

## ⚠️ Important Notes

1. **LocalStack is ephemeral**: All resources are lost on restart
2. **Order matters**: S3 Notifications MUST be set before upload
3. **Lambda size**: ZIPs with NLTK data are optimized (~3-5MB instead of 63MB)
4. **Performance**: Pipeline may take several minutes for many reviews

## 🛠️ Development

### Modify Lambda Functions
1. Edit Python files in `src/lambdas/`
2. Run Option 4 (create new ZIPs)
3. Run Option 5 (redeploy Lambdas)

### Add New Lambda
1. Create `src/lambdas/new_lambda.py`
2. Update `workflows.sh`
3. Extend `notification-config.json`

