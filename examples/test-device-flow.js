#!/usr/bin/env node

/**
 * Keycloak Device Flow Test Application
 * 
 * This script demonstrates how to implement OAuth 2.0 Device Authorization Grant
 * with Keycloak.
 * 
 * Usage:
 *   npm install axios
 *   node test-device-flow.js
 */

const https = require('https');
const http = require('http');
const { URL } = require('url');

// Configuration
const KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://localhost:8080';
const REALM = process.env.KEYCLOAK_REALM || 'hybrid-auth';
const CLIENT_ID = process.env.CLIENT_ID || 'device-flow-client';
const CLIENT_SECRET = process.env.CLIENT_SECRET || ''; // Set this to your client secret

// Keycloak endpoints
const DEVICE_ENDPOINT = `${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device`;
const TOKEN_ENDPOINT = `${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token`;
const USERINFO_ENDPOINT = `${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo`;

/**
 * Make HTTP request
 */
function makeRequest(url, options = {}) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        const lib = urlObj.protocol === 'https:' ? https : http;
        
        const req = lib.request(url, options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(data);
                    resolve({ status: res.statusCode, data: parsed });
                } catch (e) {
                    resolve({ status: res.statusCode, data });
                }
            });
        });
        
        req.on('error', reject);
        
        if (options.body) {
            req.write(options.body);
        }
        
        req.end();
    });
}

/**
 * Step 1: Initiate device authorization
 */
async function initiateDeviceFlow() {
    console.log('🚀 Starting Device Authorization Flow...');
    console.log(`📡 Keycloak URL: ${KEYCLOAK_URL}`);
    console.log(`🏰 Realm: ${REALM}`);
    console.log(`🔑 Client ID: ${CLIENT_ID}`);
    console.log();

    const body = new URLSearchParams({
        client_id: CLIENT_ID,
        scope: 'openid profile email'
    });

    try {
        const response = await makeRequest(DEVICE_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(body.toString())
            },
            body: body.toString()
        });

        if (response.status !== 200) {
            throw new Error(`HTTP ${response.status}: ${JSON.stringify(response.data)}`);
        }

        return response.data;
    } catch (error) {
        console.error('❌ Failed to initiate device flow:', error.message);
        throw error;
    }
}

/**
 * Step 2: Poll for authorization
 */
async function pollForAuthorization(deviceCode, interval) {
    console.log('⏳ Polling for user authorization...');
    
    const body = new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        device_code: deviceCode,
        client_id: CLIENT_ID
    });

    if (CLIENT_SECRET) {
        body.append('client_secret', CLIENT_SECRET);
    }

    let attempts = 0;
    const maxAttempts = 60; // 5 minutes with 5-second intervals

    while (attempts < maxAttempts) {
        try {
            const response = await makeRequest(TOKEN_ENDPOINT, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'Content-Length': Buffer.byteLength(body.toString())
                },
                body: body.toString()
            });

            if (response.status === 200) {
                console.log('✅ Authorization successful!');
                return response.data;
            }

            if (response.data.error === 'authorization_pending') {
                process.stdout.write('.');
                await new Promise(resolve => setTimeout(resolve, interval * 1000));
                attempts++;
                continue;
            }

            if (response.data.error === 'slow_down') {
                console.log('\n⚠️  Slowing down polling...');
                await new Promise(resolve => setTimeout(resolve, (interval + 5) * 1000));
                continue;
            }

            throw new Error(`Authorization failed: ${response.data.error} - ${response.data.error_description}`);

        } catch (error) {
            console.error('\n❌ Polling error:', error.message);
            throw error;
        }
    }

    throw new Error('❌ Authorization timed out');
}

/**
 * Step 3: Get user info
 */
async function getUserInfo(accessToken) {
    try {
        const response = await makeRequest(USERINFO_ENDPOINT, {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${accessToken}`
            }
        });

        if (response.status !== 200) {
            throw new Error(`HTTP ${response.status}: ${JSON.stringify(response.data)}`);
        }

        return response.data;
    } catch (error) {
        console.error('❌ Failed to get user info:', error.message);
        throw error;
    }
}

/**
 * Main execution
 */
async function main() {
    try {
        // Step 1: Initiate device flow
        const deviceAuth = await initiateDeviceFlow();
        
        console.log('🔐 Device Authorization Response:');
        console.log(`   Device Code: ${deviceAuth.device_code}`);
        console.log(`   User Code: ${deviceAuth.user_code}`);
        console.log(`   Verification URI: ${deviceAuth.verification_uri}`);
        console.log(`   Complete URI: ${deviceAuth.verification_uri_complete}`);
        console.log(`   Expires in: ${deviceAuth.expires_in} seconds`);
        console.log(`   Polling interval: ${deviceAuth.interval} seconds`);
        console.log();
        
        console.log('👤 Next steps for the user:');
        console.log(`   1. Open: ${deviceAuth.verification_uri}`);
        console.log(`   2. Enter code: ${deviceAuth.user_code}`);
        console.log('   3. Sign in with your Keycloak credentials');
        console.log();
        
        console.log('🔗 Quick link (copy and paste):');
        console.log(`   ${deviceAuth.verification_uri_complete}`);
        console.log();

        // Step 2: Poll for authorization
        const tokenResponse = await pollForAuthorization(
            deviceAuth.device_code,
            deviceAuth.interval
        );
        
        console.log();
        console.log('🎉 Token Response:');
        console.log(`   Access Token: ${tokenResponse.access_token.substring(0, 50)}...`);
        console.log(`   Token Type: ${tokenResponse.token_type}`);
        console.log(`   Expires In: ${tokenResponse.expires_in} seconds`);
        console.log(`   Refresh Token: ${tokenResponse.refresh_token ? 'Present' : 'Not provided'}`);
        console.log(`   ID Token: ${tokenResponse.id_token ? 'Present' : 'Not provided'}`);
        console.log();

        // Step 3: Get user information
        console.log('👤 Getting user information...');
        const userInfo = await getUserInfo(tokenResponse.access_token);
        
        console.log('✅ User Information:');
        console.log(`   Username: ${userInfo.preferred_username || userInfo.sub}`);
        console.log(`   Email: ${userInfo.email || 'Not provided'}`);
        console.log(`   Name: ${userInfo.name || 'Not provided'}`);
        console.log(`   Subject: ${userInfo.sub}`);
        console.log();

        console.log('🎊 Device flow completed successfully!');
        
        // Optional: Show full token details
        if (process.argv.includes('--verbose')) {
            console.log();
            console.log('🔍 Full Token Response:');
            console.log(JSON.stringify(tokenResponse, null, 2));
            console.log();
            console.log('🔍 Full User Info:');
            console.log(JSON.stringify(userInfo, null, 2));
        }

    } catch (error) {
        console.error('💥 Device flow failed:', error.message);
        
        console.log();
        console.log('🔧 Troubleshooting:');
        console.log('   1. Ensure Keycloak is running: ./network-info.sh');
        console.log('   2. Check realm exists and device flow is enabled');
        console.log('   3. Verify client configuration');
        console.log('   4. Check network connectivity');
        console.log(`   5. Verify Keycloak URL: ${KEYCLOAK_URL}`);
        
        process.exit(1);
    }
}

// Handle command line arguments
if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log('Keycloak Device Flow Test Application');
    console.log();
    console.log('Usage:');
    console.log('  node test-device-flow.js [options]');
    console.log();
    console.log('Options:');
    console.log('  --verbose    Show full token and user info details');
    console.log('  --help, -h   Show this help message');
    console.log();
    console.log('Environment Variables:');
    console.log('  KEYCLOAK_URL     Keycloak base URL (default: http://localhost:8080)');
    console.log('  KEYCLOAK_REALM   Realm name (default: hybrid-auth)');
    console.log('  CLIENT_ID        OAuth client ID (default: device-flow-client)');
    console.log('  CLIENT_SECRET    OAuth client secret (required for confidential clients)');
    console.log();
    console.log('Example:');
    console.log('  KEYCLOAK_URL=http://192.168.1.103:8080 CLIENT_SECRET=your-secret node test-device-flow.js');
    process.exit(0);
}

// Run the main function
if (require.main === module) {
    main();
}
