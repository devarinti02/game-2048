# Using official Nginx image
FROM nginx:alpine

# Removing, the default nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copying static website files to Nginx public directorya topi
COPY . /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Start Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
