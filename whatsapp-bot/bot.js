// whatsapp-bot/bot.js
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — WhatsApp AI Assistant
// Powered by @whiskeysockets/baileys (WhatsApp Web socket) & Google Gemini 1.5 Flash
// ═══════════════════════════════════════════════════════════════════════

import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  Browsers,
} from '@whiskeysockets/baileys';
import qrcode from 'qrcode-terminal';
import pino from 'pino';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AUTH_DIR = path.join(__dirname, 'auth_info_baileys');

// ─── Gemini Configuration & Conversation Memory ─────────────────────
const GEMINI_API_KEY = (process.env.GEMINI_API_KEY || '').trim();
const GEMINI_MODEL = (process.env.GEMINI_MODEL || 'gemini-3.8-flash').trim();

const SYSTEM_PROMPT = `You are the official Vektolux AI Assistant on WhatsApp for Sierra Leone.
Your job is to answer questions, build confidence, and explain how Vektolux works.
Key facts about Vektolux:
- Digital marketplace for Sierra Leone featuring verified Real Estate and Auto Market listings.
- Escrow Protection: Buyers pay into the Vektolux Escrow Wallet. Funds are held safely and only disbursed to the seller when goods/property are inspected and approved.
- Mobile Money Integration: Direct top-ups and payouts via Orange Money, Africell Afrimoney, and QMoney using carrier USSD prompts (*715*...#).
- Minimal 1% escrow fee.
Keep replies friendly, professional, clear, and concise (ideal for WhatsApp chats). Use short bullet points when listing steps.`;

// In-memory conversation history per WhatsApp user (stores last 8 turns)
const userSessions = new Map();
const MAX_HISTORY = 8;

// Anti-loop protection & bot message identifier (invisible zero-width space)
const BOT_WATERMARK = '\u200B';
const sentMessageIds = new Set();

function normalizeJid(jid) {
  if (!jid) return '';
  return jid.split(':')[0].replace(/@.*$/, '') + '@s.whatsapp.net';
}

/**
 * Generate AI reply using Google Gemini via REST API
 */
async function generateGeminiResponse(userId, userMessage) {
  if (!GEMINI_API_KEY) {
    console.warn('[Gemini Warning] GEMINI_API_KEY is not set in .env. Returning default welcome response.');
    return (
      `Hello! Welcome to Vektolux 🇸🇱\n\n` +
      `We are Sierra Leone's trusted digital marketplace for verified Real Estate and Vehicles with built-in Escrow Protection.\n\n` +
      `• *Website*: https://vektolux.com\n` +
      `• *Escrow Fee*: Only 1%\n` +
      `• *Mobile Money*: Orange Money, Africell, QMoney\n\n` +
      `_Note: Set GEMINI_API_KEY in whatsapp-bot/.env to enable autonomous AI conversations._`
    );
  }

  // Get or initialize user history
  if (!userSessions.has(userId)) {
    userSessions.set(userId, []);
  }
  const history = userSessions.get(userId);

  // Append new user message to history
  history.push({
    role: 'user',
    parts: [{ text: userMessage }],
  });

  // Keep history manageable
  while (history.length > MAX_HISTORY) {
    history.shift();
  }

  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(GEMINI_API_KEY)}`;

  const requestBody = {
    systemInstruction: {
      parts: [{ text: SYSTEM_PROMPT }],
    },
    contents: history,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 800,
    },
  };

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': GEMINI_API_KEY,
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error(`[Gemini API Error] HTTP ${response.status}:`, errText);
      return "I'm having a brief issue connecting to my knowledge base. Please try asking again in a few seconds!";
    }

    const data = await response.json();
    const candidate = data?.candidates?.[0];
    const replyText = candidate?.content?.parts?.[0]?.text?.trim();

    if (!replyText) {
      return "I received your message! How can I assist you with Vektolux's real estate, vehicle listings, or escrow services?";
    }

    // Append assistant response to history
    history.push({
      role: 'model',
      parts: [{ text: replyText }],
    });

    return replyText;
  } catch (error) {
    console.error('[Gemini Network Error]:', error);
    return "I'm having trouble connecting right now. Please try again shortly!";
  }
}

// ─── Baileys WhatsApp Socket Lifecycle ─────────────────────────────
async function startBot() {
  console.log('🔄 Initializing Vektolux WhatsApp AI Assistant...');

  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version, isLatest } = await fetchLatestBaileysVersion();
  console.log(`📡 Using Baileys version ${version.join('.')} (isLatest: ${isLatest})`);

  const sock = makeWASocket({
    version,
    logger: pino({ level: 'silent' }), // Suppress noisy protocol logs
    printQRInTerminal: false, // Handled manually below for clean formatting
    auth: state,
    browser: Browsers.macOS('Desktop'),
    syncFullHistory: false,
    generateHighQualityLinkPreview: true,
  });

  // Credential persistence
  sock.ev.on('creds.update', saveCreds);

  // Connection monitoring and QR code display
  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      console.log('\n╔══════════════════════════════════════════════════════════════════╗');
      console.log('║        📱 SCAN THIS QR CODE WITH YOUR WHATSAPP TO LINK BOT       ║');
      console.log('║  (Open WhatsApp -> Settings / 3 Dots -> Linked Devices -> Link)  ║');
      console.log('╚══════════════════════════════════════════════════════════════════╝\n');
      qrcode.generate(qr, { small: true });
    }

    if (connection === 'close') {
      const statusCode = lastDisconnect?.error?.output?.statusCode;
      const shouldReconnect = statusCode !== DisconnectReason.loggedOut;
      console.log(`⚠️ Connection closed (status: ${statusCode}). Reconnecting: ${shouldReconnect}`);

      if (shouldReconnect) {
        setTimeout(startBot, 3000);
      } else {
        console.log('❌ Logged out from WhatsApp. Clear auth_info_baileys/ and restart to scan new QR.');
      }
    } else if (connection === 'open') {
      console.log('\n🚀 ✅ [Vektolux WhatsApp Bot] Connected successfully! Listening for messages...\n');
    }
  });

  // Message listener (supports external users and self-testing)
  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;

    for (const m of messages) {
      try {
        const from = m.key.remoteJid;
        // Accept messages from private chats (@s.whatsapp.net)
        if (!from || !from.endsWith('@s.whatsapp.net')) continue;

        // Extract textual content
        const text =
          m.message?.conversation ||
          m.message?.extendedTextMessage?.text ||
          m.message?.imageMessage?.caption ||
          m.message?.videoMessage?.caption ||
          '';

        const cleanText = text.trim();
        if (!cleanText) continue;

        // 1. Loop protection: Ignore if this message was sent by the AI bot
        if (m.key.id && sentMessageIds.has(m.key.id)) continue;
        if (cleanText.includes(BOT_WATERMARK)) continue;

        // 2. Identify sender & distinguish self-chat from messages sent to external contacts
        const rawMe = sock.user?.id || state.creds?.me?.id;
        const myJid = rawMe ? normalizeJid(rawMe) : null;
        const fromJid = normalizeJid(from);
        const isSelfChat = Boolean(myJid && fromJid === myJid);

        // If the message is marked fromMe, only process it if it's self-chat (user testing on their own number)
        if (m.key.fromMe && !isSelfChat) {
          continue; // User sent a regular message to someone else; ignore
        }

        const chatLabel = isSelfChat ? `[Self-Chat ${fromJid}]` : `from ${from}`;
        console.log(`📩 [WhatsApp Incoming] ${chatLabel}: "${cleanText}"`);

        // Send 'typing...' presence update
        await sock.sendPresenceUpdate('composing', from);

        // Generate response with Gemini
        const reply = await generateGeminiResponse(from, cleanText);

        // Turn off typing indicator
        await sock.sendPresenceUpdate('paused', from);

        // Dispatch reply back to the chat tagged with invisible watermark
        const taggedReply = reply + BOT_WATERMARK;
        const sent = await sock.sendMessage(from, { text: taggedReply });

        if (sent?.key?.id) {
          sentMessageIds.add(sent.key.id);
          if (sentMessageIds.size > 200) {
            const first = sentMessageIds.values().next().value;
            sentMessageIds.delete(first);
          }
        }

        console.log(`📤 [WhatsApp Outgoing] to ${from}: "${reply.slice(0, 80).replace(/\n/g, ' ')}..."`);
      } catch (msgErr) {
        console.error('[Error handling message]:', msgErr);
      }
    }
  });
}

// Start bot
startBot().catch((err) => {
  console.error('[Fatal Error starting bot]:', err);
});
