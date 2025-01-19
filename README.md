# Premium Web Application Deployment Guide

This guide will help you set up this premium web application template with your own infrastructure (DigitalOcean, Supabase, custom domain, etc.).

## Prerequisites

- A DigitalOcean account
- A Supabase account
- A domain name
- A Stripe account
- Git installed on your local machine
- Basic knowledge of terminal/command line

## Step 1: Clone and Configure Repository

1. Clone the repository to your local machine:
```bash
git clone <repository-url>
cd webapp
```

2. Create a new GitHub repository for your project and update the remote:
```bash
git remote remove origin
git remote add origin <your-new-repo-url>
```

## Step 2: Infrastructure Setup

### A. DigitalOcean Droplet Setup
1. Create a new Ubuntu droplet on DigitalOcean
   - Choose Ubuntu 22.04 LTS
   - Select Basic plan (minimum 2GB RAM recommended)
   - Choose a datacenter region close to your target audience
   - Add your SSH key
   - Create droplet

2. Note your droplet's IP address for later use

### B. Supabase Database Setup
1. Create a new project in Supabase
2. Go to Project Settings → Database
3. Copy the database connection string (format: `postgresql://postgres:[YOUR-PASSWORD]@db.[YOUR-PROJECT-REF].supabase.co:5432/postgres`)

### C. Domain Configuration
1. Go to your domain registrar
2. Add these DNS records:
   ```
   A Record:
   - Host: @ or your domain
   - Points to: Your DigitalOcean Droplet IP

   A Record:
   - Host: www
   - Points to: Your DigitalOcean Droplet IP
   ```
3. Wait for DNS propagation (can take up to 48 hours)

### D. Stripe Setup
1. Create a Stripe account
2. Get your API keys from the Stripe Dashboard
   - Publishable key
   - Secret key

## Step 3: Configuration Files Update

### A. Environment Variables (.env)
Create a new `.env` file in the webapp directory:
```env
DEBUG=False
SECRET_KEY=your-secure-secret-key
ALLOWED_HOSTS=your-domain.com,www.your-domain.com
CSRF_TRUSTED_ORIGINS=https://your-domain.com,https://www.your-domain.com
DATABASE_URL=your-supabase-connection-string
STRIPE_PUBLISHABLE_KEY=your-stripe-publishable-key
STRIPE_SECRET_KEY=your-stripe-secret-key
SUBSCRIPTION_PRICE_AMOUNT=500
SITE_URL=https://your-domain.com
```

### B. Nginx Configuration
Update `webapp/nginx/nginx.conf`:
```nginx
server_name your-domain.com www.your-domain.com;
ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
```

### C. SSL Certificate Script
Update `webapp/init-letsencrypt.sh`:
```bash
domains=(your-domain.com www.your-domain.com)
email="your-email@example.com"    # Adding a valid address is strongly recommended
```

Make the script executable:
```bash
chmod +x init-letsencrypt.sh
```

### D. Django Settings
Update `webapp/core/settings.py`:
```python
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'your-domain.com,www.your-domain.com').split(',')
CSRF_TRUSTED_ORIGINS = os.getenv('CSRF_TRUSTED_ORIGINS', 'https://your-domain.com,https://www.your-domain.com').split(',')
SITE_URL = 'https://your-domain.com'
```

## Step 4: Deployment

1. Push your changes to your new repository:
```bash
git add .
git commit -m "Initial configuration"
git push origin main
```

2. SSH into your DigitalOcean droplet:
```bash
ssh root@your-droplet-ip
```

3. Install Git and clone your repository:
```bash
apt update
apt install git
cd ~
git clone <your-new-repo-url>
cd webapp
```

4. Initialize SSL certificates:
```bash
./init-letsencrypt.sh
```

5. Deploy the application:
```bash
./deploy.sh
```

## Step 5: Verify Deployment

1. Visit your domain (https://your-domain.com)
2. Test user registration and login
3. Test Stripe subscription
4. Test the desktop application connection

## Common Issues and Troubleshooting

### Database Connection Issues
- Verify your Supabase connection string
- Check if the IP of your droplet is allowed in Supabase

### SSL Certificate Issues
- Ensure DNS propagation is complete
- Check if ports 80 and 443 are open on your droplet
- Verify domain configuration in nginx.conf

### Stripe Integration Issues
- Verify your Stripe API keys
- Check webhook configuration
- Test with Stripe test mode first

## Security Considerations

1. Update the Django SECRET_KEY
2. Use strong passwords for:
   - Database
   - Admin account
   - Server access

3. Keep your .env file secure and never commit it to version control

4. Regularly update dependencies:
```bash
pip install -r requirements.txt --upgrade
```

## Maintenance

### Regular Updates
```bash
# SSH into your server
ssh root@your-droplet-ip

# Pull latest changes
cd ~/webapp
git pull

# Deploy updates
./deploy.sh
```

### Backup Database
Regularly backup your Supabase database using their dashboard or API

### Monitor Logs
```bash
# View application logs
docker-compose logs -f web

# View nginx logs
docker-compose logs -f nginx
```

## Support and Resources

- [DigitalOcean Documentation](https://docs.digitalocean.com)
- [Supabase Documentation](https://supabase.io/docs)
- [Stripe Documentation](https://stripe.com/docs)
- [Django Documentation](https://docs.djangoproject.com)

## License

This project is licensed under the MIT License - see the LICENSE file for details 