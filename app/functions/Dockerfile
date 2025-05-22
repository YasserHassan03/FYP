# Use the official Python image
FROM python:3.11-slim

# Set the working directory
WORKDIR /app

# Copy the application files
COPY . /app

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port Cloud Run will use
EXPOSE 8080

# Command to run the application
CMD ["python", "main.py"]