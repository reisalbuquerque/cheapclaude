#!/usr/bin/env node
import { startModelProxy } from './model-proxy.js';
import { writeFileSync, unlinkSync } from 'fs';
import { join } from 'path';

const BACKEND_DEFS = {
    deepseek: { url: 'https://api.deepseek.com/anthropic', keyEnv: 'DEEPSEEK_API_KEY' },
    openrouter: { url: 'https://openrouter.ai/api/v1', keyEnv: 'OPENROUTER_API_KEY' },
    fireworks: { url: 'https://api.fireworks.ai/inference/v1', keyEnv: 'FIREWORKS_API_KEY' },
    dashscope: { url: 'https://coding-intl.dashscope.aliyuncs.com/apps/anthropic', keyEnv: 'DASHSCOPE_API_KEY' },
    kimi: { url: 'https://api.moonshot.ai/anthropic', keyEnv: 'KIMI_API_KEY' },
    mimo: { url: 'https://token-plan-sgp.xiaomimimo.com/anthropic', keyEnv: 'MIMO_API_KEY' },
};

// Legacy mode: start-proxy.js <targetUrl> <apiKey> [modeName] (used by deepclaude.sh/ps1)
const targetUrl = process.argv[2] || process.env.CHEAPCLAUDE_TARGET_URL;
const apiKey = process.argv[3] || process.env.CHEAPCLAUDE_API_KEY;
const modeName = process.argv[4];  // optional: deepseek, openrouter, fireworks

if (targetUrl && apiKey) {
    // Legacy single-backend mode
    const backends = {};
    for (const [name, def] of Object.entries(BACKEND_DEFS)) {
        const key = process.env[def.keyEnv];
        backends[name] = { url: def.url, apiKey: key || null };
    }

    // Register proxy state for --list / --switch --port
    const stateFile = join(process.env.TMPDIR || '/tmp', `deepclaude-proxy-${process.pid}.json`);
    const initialStateData = JSON.stringify({ pid: process.pid, port: 0, mode: modeName || 'unknown', started: Date.now() });
    writeFileSync(stateFile, initialStateData);

    const { port } = await startModelProxy({
        targetUrl,
        apiKey,
        backends,
        defaultMode: modeName || undefined,
        stateFile,
    });
    console.log(port);

    // Update state file with actual port after proxy starts
    const stateData = JSON.stringify({ pid: process.pid, port, mode: modeName || 'unknown', started: Date.now() });
    writeFileSync(stateFile, stateData);

    const cleanup = () => { try { unlinkSync(stateFile); } catch {} process.exit(0); };
    process.on('SIGTERM', cleanup);
    process.on('SIGINT', cleanup);
    process.on('SIGHUP', cleanup);
} else {
    // Standalone mode with live toggle
    const backends = {};
    for (const [name, def] of Object.entries(BACKEND_DEFS)) {
        const key = process.env[def.keyEnv];
        backends[name] = { url: def.url, apiKey: key || null };
    }

    const fallbackUrl = backends.deepseek?.url || 'https://api.deepseek.com/anthropic';
    const fallbackKey = backends.deepseek?.apiKey || 'unused';

    const args = process.argv.slice(2);
    const modeFlag = args.indexOf('--mode');
    const defaultMode = modeFlag >= 0 ? args[modeFlag + 1] : 'anthropic';
    const portFlag = args.indexOf('--port');
    const port = portFlag >= 0 ? parseInt(args[portFlag + 1], 10) : 3200;

    // Register proxy state for --list / --switch --port
    const stateFile = join(process.env.TMPDIR || '/tmp', `deepclaude-proxy-${process.pid}.json`);
    const initialStateData = JSON.stringify({ pid: process.pid, port, mode: defaultMode, started: Date.now() });
    writeFileSync(stateFile, initialStateData);

    const proxy = await startModelProxy({
        targetUrl: fallbackUrl,
        apiKey: fallbackKey,
        startPort: port,
        backends,
        defaultMode,
        stateFile,
    });

    // Update state file with actual port after proxy starts (may differ due to auto-allocation)
    const updatedState = JSON.stringify({ pid: process.pid, port: proxy.port, mode: defaultMode, started: Date.now() });
    writeFileSync(stateFile, updatedState);

    console.log(`Proxy on :${proxy.port} (mode: ${defaultMode})`);

    const cleanup = () => { try { unlinkSync(stateFile); } catch {} process.exit(0); };
    process.on('SIGTERM', cleanup);
    process.on('SIGINT', cleanup);
    process.on('SIGHUP', cleanup);
}
