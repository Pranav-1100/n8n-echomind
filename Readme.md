# EchoMind

## Overview

EchoMind is an AI-powered personal memory and productivity assistant built using n8n.

The goal of this project is to help users store important conversations, retrieve them later using natural language, and automatically manage incoming emails. Instead of manually searching through notes, chats, or emails, users can simply ask questions and let the system find the relevant information.

This project demonstrates agentic workflow design by combining AI reasoning, deterministic logic, vector databases, workflow automation, and error handling.

---

## Problem Statement

As students and developers, we participate in many discussions every week including project meetings, mentor calls, hackathons, research discussions, and email conversations.

Important decisions and information are often forgotten after a few days.

EchoMind solves this problem by:

* Capturing conversation transcripts
* Extracting useful information using AI
* Storing memories for future retrieval
* Allowing natural language search over past conversations
* Automatically prioritizing important emails

---

## Tech Stack

* n8n
* Groq (Llama 3.3 70B)
* Pinecone Vector Database
* Hugging Face Embeddings
* Google Sheets
* Gmail API

---

# Workflow 1: Memory Ingestion Pipeline

### Purpose

Convert raw conversation transcripts into structured and searchable memories.

### Workflow

1. Receive transcript through a webhook.
2. Validate that transcript data exists.
3. Detect emotion using Llama 3.3 70B.
4. Check confidence score using a deterministic IF node.
5. Classify the conversation topic.
6. Generate a concise summary.
7. Store structured data in Google Sheets.
8. Generate embeddings.
9. Store memories in Pinecone for semantic search.

### AI Tasks

* Emotion Detection
* Topic Classification
* Summary Generation

### Deterministic Tasks

* Input Validation
* Confidence Threshold Check
* Data Storage
* Workflow Routing

---

# Workflow 2: Memory Recall Assistant

### Purpose

Allow users to retrieve past conversations using natural language questions.

### Workflow

1. Receive user query through chat.
2. Parse user intent using AI.
3. Determine retrieval strategy.
4. Search Pinecone for relevant memories.
5. Aggregate retrieved results.
6. Generate a final answer based only on retrieved memories.

### Example Query

"What is the latest update on the security pentesting project with Aditya, and what platform are we targeting next?"

---

# Workflow 3: Inbox Shield

### Purpose

Automatically summarize and prioritize incoming emails.

### Workflow

1. Monitor unread Gmail messages.
2. Generate an email summary using AI.
3. Classify email priority using AI.
4. Merge results.
5. Store summaries in Google Sheets.
6. If email is urgent, automatically apply an Important label.

### AI Tasks

* Email Summarization
* Priority Classification

### Deterministic Tasks

* Label Assignment
* Conditional Routing
* Logging

---

# Workflow 4: Global Error Handler

### Purpose

Provide centralized monitoring for workflow failures.

### Workflow

1. Capture workflow execution failures.
2. Record timestamp, workflow name, failed node, and error message.
3. Store error logs in Google Sheets.

---

## Agentic Design Concepts Demonstrated

This project demonstrates multiple agentic workflow concepts:

* Task Decomposition
* Multiple AI Agents
* Tool Usage
* Structured Outputs
* Routing Logic
* Deterministic Validation
* Vector Search
* Retrieval-Augmented Generation (RAG)
* Error Handling

---

## Sample Input

```json
{
  "speaker": "Aditya Singh",
  "transcript": "We finally got the Model Context Protocol working with Claude for the security pentesting project. Let us focus on scaling it for Code4rena next."
}
```

## Sample Output

```json
{
  "emotion": "excited",
  "topic": "coding",
  "summary": "The discussion focused on successfully integrating Model Context Protocol with Claude for a security pentesting project and planning future scaling efforts for Code4rena."
}
```

---

## Future Improvements

* Real-time audio ingestion
* Mobile application
* Human-in-the-loop review interface
* Custom backend service
* Speaker identification
* Real-time meeting integration

---

## Author

Pranav Aggarwal
