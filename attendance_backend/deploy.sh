#!/bin/bash
# Deploy script for Face Attendance Backend (No Git Version)
# This script rebuilds and restarts the Docker container

echo "🚀 Starting deployment..."

# Navigate to project directory
cd /home/ubuntu/apps/attendance_backend

# Build new Docker image
echo "🔨 Building Docker image..."
docker build -t attendance-backend .

# Stop and remove old container (if exists)
echo "🛑 Stopping old container..."
docker stop attendance-backend 2>/dev/null
docker rm attendance-backend 2>/dev/null

# Start new container with database persistence
echo "▶️ Starting new container..."
docker run -d \
  --name attendance-backend \
  -p 8100:8100 \
  -v /home/ubuntu/apps/attendance_backend/attendance.db:/app/attendance.db \
  --restart unless-stopped \
  attendance-backend

# Wait a moment and check if it's running
sleep 3
if docker ps | grep -q attendance-backend; then
  echo ""
  echo "✅ Deployment successful!"
  echo "🌐 Backend running at: http://13.51.55.238:8100"
  echo ""
  docker logs --tail 10 attendance-backend
else
  echo "❌ Deployment failed! Check logs:"
  docker logs attendance-backend
fi
