# Production Deployment Checklist

This checklist ensures a successful production deployment of WandererNotifier.

## Pre-Deployment

### ✅ Environment Setup

#### Required Environment Variables
- [ ] `DISCORD_BOT_TOKEN` - Valid Discord bot token
- [ ] `DISCORD_APPLICATION_ID` - Discord application ID for slash commands
- [ ] `DISCORD_CHANNEL_ID` - Primary notification channel ID
- [ ] `MAP_URL` - Wanderer map base URL (e.g., "https://wanderer.ltd")
- [ ] `MAP_NAME` - Map slug/name
- [ ] `MAP_API_KEY` - Valid map API authentication key
- [ ] `LICENSE_KEY` - Valid license key for premium features

#### Optional Environment Variables
- [ ] `DISCORD_SYSTEM_CHANNEL_ID` - Dedicated system notifications channel
- [ ] `DISCORD_CHARACTER_CHANNEL_ID` - Dedicated character notifications channel
- [ ] `DISCORD_SYSTEM_KILL_CHANNEL_ID` - System-based kill notifications
- [ ] `DISCORD_CHARACTER_KILL_CHANNEL_ID` - Character-based kill notifications
- [ ] `WEBSOCKET_URL` - WandererKills WebSocket URL (default: "ws://host.docker.internal:4004")
- [ ] `WANDERER_KILLS_URL` - WandererKills API URL (default: "http://host.docker.internal:4004")

#### Production Configuration
- [ ] `MIX_ENV=prod` - Production environment
- [ ] `PORT=4000` - Web server port
- [ ] `ENABLE_STATUS_MESSAGES=false` - Disable startup status messages
- [ ] `LOG_LEVEL=info` - Appropriate logging level

#### Feature Flags (Review & Configure)
- [ ] `NOTIFICATIONS_ENABLED=true` - Master notification toggle
- [ ] `KILL_NOTIFICATIONS_ENABLED=true` - Kill notifications
- [ ] `SYSTEM_NOTIFICATIONS_ENABLED=true` - System notifications
- [ ] `CHARACTER_NOTIFICATIONS_ENABLED=true` - Character notifications
- [ ] `PRIORITY_SYSTEMS_ONLY=false` - Priority-only mode
- [ ] `TRACK_KSPACE_ENABLED=true` - K-Space tracking

### ✅ Discord Bot Setup

#### Bot Configuration
- [ ] Bot created in Discord Developer Portal
- [ ] Bot token generated and securely stored
- [ ] Application ID recorded
- [ ] Bot invited to Discord server with required permissions:
  - [ ] Send Messages
  - [ ] Use Slash Commands
  - [ ] Mention Everyone (for @here notifications)
  - [ ] Embed Links
  - [ ] Attach Files

#### Channel Setup
- [ ] Primary notification channel created and ID recorded
- [ ] Optional dedicated channels created (system, character, kills)
- [ ] Bot has access to all configured channels
- [ ] Test message sent to verify bot permissions

### ✅ External Service Validation

#### Map API
- [ ] Map URL accessible and responding
- [ ] API key valid and has required permissions
- [ ] Map name/slug verified to exist
- [ ] Test API call successful: `curl -H "Authorization: Bearer $MAP_API_KEY" "$MAP_URL/api/maps/$MAP_NAME/systems"`

#### License Service
- [ ] License key valid and active
- [ ] License manager URL accessible: `https://lm.wanderer.ltd`
- [ ] License validation test successful

#### WandererKills Service
- [ ] WebSocket URL accessible
- [ ] HTTP API URL accessible
- [ ] Service responding to health checks

## Deployment

### ✅ Docker Deployment

#### Image Build
- [ ] Latest code pulled from main branch
- [ ] Docker image built successfully: `make docker.build`
- [ ] Image tagged appropriately for production
- [ ] Image pushed to registry (if using)

#### Container Runtime
- [ ] Docker Compose configuration reviewed
- [ ] Environment variables file (`.env`) properly configured
- [ ] Volume mounts configured for persistence:
  - [ ] `./priv:/app/priv` - For persistent data
- [ ] Network configuration allows external access to health endpoints
- [ ] Resource limits configured (memory, CPU)

#### Deployment Commands
```bash
# Build and start
docker-compose up -d

# Verify container is running
docker-compose ps

# Check logs
docker-compose logs -f wanderer-notifier
```

### ✅ Alternative Deployment (Direct)

#### Release Build
- [ ] Production release built: `make release`
- [ ] Release artifact tested
- [ ] Environment variables exported
- [ ] Required directories created:
  - [ ] `priv/` - For persistent data
  - [ ] `log/` - For log files (if file logging enabled)

#### Service Configuration
- [ ] Systemd service file created (if using systemd)
- [ ] Service configured to start on boot
- [ ] Appropriate user/group permissions set
- [ ] Log rotation configured

## Post-Deployment Verification

### ✅ Health Checks

#### Application Health
- [ ] Health endpoint responding: `curl http://localhost:4000/health`
- [ ] Readiness check passing: `curl http://localhost:4000/ready`
- [ ] System info accessible: `curl http://localhost:4000/api/system/info`

#### Service Status
- [ ] All supervision tree processes started successfully
- [ ] WebSocket connection established to WandererKills
- [ ] SSE connection established to map API
- [ ] Discord bot online and responsive

### ✅ Integration Testing

#### Discord Bot
- [ ] Slash commands registered: Check logs for "Successfully registered Discord slash commands"
- [ ] Test `/notifier status` command
- [ ] Test system management: `/notifier system TestSystem action:add-priority`
- [ ] Verify command persistence across bot restart

#### Notification Pipeline
- [ ] License validation successful
- [ ] Map data initialization complete
- [ ] Cache warming completed
- [ ] No critical errors in startup logs

#### External Connections
- [ ] WebSocket connection status: Check logs for killmail WebSocket connection
- [ ] SSE connection status: Check logs for map SSE connection
- [ ] Discord connection stable: Bot shows online in Discord

### ✅ Monitoring Setup

#### Log Monitoring
- [ ] Application logs accessible and structured
- [ ] Error aggregation configured (if applicable)
- [ ] Log retention policy implemented
- [ ] Critical error alerting configured

#### Metrics Collection
- [ ] Health check monitoring in place
- [ ] Performance metrics collection active
- [ ] Connection status monitoring
- [ ] Notification delivery tracking

#### Alerting
- [ ] Health check failures alert configured
- [ ] Service restart alerts
- [ ] External service connectivity alerts
- [ ] Discord bot offline alerts

## Production Verification Script

Run the included verification script:

```bash
# Make executable and run
chmod +x scripts/production_deployment_verification.sh
./scripts/production_deployment_verification.sh
```

This script performs comprehensive checks of:
- Environment variable validation
- Service connectivity
- Health endpoints
- Discord bot functionality
- External service integration

## Operational Procedures

### ✅ Backup & Recovery

#### Data Backup
- [ ] Persistent data backup strategy: `priv/persistent_values.bin`, `priv/command_log.bin`
- [ ] Configuration backup: Environment variables, Docker Compose files
- [ ] Recovery procedure documented and tested

#### Disaster Recovery
- [ ] Backup restoration procedure documented
- [ ] Recovery time objective (RTO) defined
- [ ] Recovery point objective (RPO) defined
- [ ] DR testing schedule established

### ✅ Maintenance

#### Updates
- [ ] Update procedure documented
- [ ] Rollback procedure defined
- [ ] Testing process for updates
- [ ] Maintenance window scheduling

#### Scaling
- [ ] Resource monitoring in place
- [ ] Scaling triggers identified
- [ ] Horizontal scaling strategy (if needed)
- [ ] Performance baseline established

## Security Checklist

### ✅ Configuration Security
- [ ] Environment variables stored securely (not in code)
- [ ] API keys rotated regularly
- [ ] Discord bot token secured
- [ ] File permissions properly configured
- [ ] No secrets in logs

### ✅ Network Security
- [ ] Firewall rules configured
- [ ] Only required ports exposed
- [ ] HTTPS used for all external communications
- [ ] Internal service communications secured

### ✅ Runtime Security
- [ ] Container runs as non-root user
- [ ] Security scanning performed on container image
- [ ] Regular security updates applied
- [ ] Access logs monitored

## Troubleshooting

### Common Issues
- **Discord commands not working**: Check application ID and bot permissions
- **WebSocket connection failures**: Verify WandererKills service accessibility
- **License validation errors**: Check license key and network connectivity
- **Map API errors**: Validate API key and map configuration
- **Missing notifications**: Check channel IDs and bot permissions

### Debug Commands
```bash
# Check container logs
docker-compose logs -f wanderer-notifier

# Interactive shell (if needed)
docker-compose exec wanderer-notifier iex

# Health check details
curl -v http://localhost:4000/ready
```

## Sign-off

### Deployment Team
- [ ] **Infrastructure Team**: Environment prepared and secured
- [ ] **Development Team**: Code reviewed and tested
- [ ] **DevOps Team**: Deployment pipeline verified
- [ ] **QA Team**: Integration testing completed

### Stakeholder Approval
- [ ] **Technical Lead**: Architecture and code quality approved
- [ ] **Product Owner**: Functionality verified
- [ ] **Operations Team**: Monitoring and procedures in place
- [ ] **Security Team**: Security review completed

### Final Verification
- [ ] All checklist items completed
- [ ] Production verification script passed
- [ ] 24-hour stability period observed
- [ ] Performance within acceptable limits
- [ ] Monitoring and alerting functional

**Deployment Date**: ________________  
**Deployed By**: ____________________  
**Version**: ________________________  
**Environment**: Production

---

## Emergency Contacts

- **On-Call Engineer**: [Contact Information]
- **Technical Lead**: [Contact Information]
- **Infrastructure Team**: [Contact Information]
- **Discord Server Admin**: [Contact Information]

## Post-Deployment Notes

_Space for deployment-specific notes, issues encountered, and resolutions_

---

*This checklist should be reviewed and updated regularly to reflect changes in the application architecture and deployment procedures.*