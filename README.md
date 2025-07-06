# 📊 DataFlow Dashboard

A modern, serverless ETL (Extract-Transform-Load) dashboard for uploading CSV files, visualizing data, and receiving technical ETL reports via email. Built with AWS Lambda, S3, DynamoDB, SNS, API Gateway, and a responsive frontend powered by HTML, Chart.js, and AI analysis.

## 🔧 Features

- ✅ Drag-and-drop CSV file upload to S3
- 🧼 Serverless ETL cleaning using Lambda:
  - Trims whitespace
  - Cleans names (Title Case)
  - Lowercases emails
  - Converts `amount` to Decimal
  - Skips malformed or empty rows
- 📨 ETL summary emailed via SNS after processing
- 📈 Data visualizations: Bar, Line, Pie, Scatter
- 🧠 Built-in AI assistant to ask questions about your data
- ☁️ Full AWS monitoring and CloudWatch alarms included

## 📦 Technologies Used

- AWS Lambda (Python)
- Amazon S3
- Amazon DynamoDB
- Amazon SNS
- Amazon API Gateway
- AWS CloudWatch Alarms
- Terraform (Infrastructure as Code)
- Frontend: HTML, Chart.js, vanilla JS
