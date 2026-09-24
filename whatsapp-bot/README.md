# Vektolux WhatsApp AI Assistant (Baileys + Gemini 1.5 Flash)

A lightweight, 100% free WhatsApp bot service for your private WhatsApp number that answers user queries about Vektolux, explains Escrow protection, and provides instant support in Sierra Leone.

---

## ⚡ Features
- **Zero WhatsApp Business API fees**: Uses `@whiskeysockets/baileys` to connect to your existing private phone number via a QR code (WhatsApp Web Linked Device).
- **Gemini 1.5 Flash Brain**: Fast, intelligent, and context-aware responses with Sierra Leone marketplace & escrow knowledge.
- **Typing Indicator**: Automatically sends typing presence (`composing`) while generating AI replies.
- **Multi-Turn Conversation Memory**: Retains recent message context per user for natural back-and-forth dialogue.
- **Auto-Reconnect**: Automatically reconnects if connection drops.

---

## 🚀 Quick Setup

### 1. Install Dependencies
```bash
cd whatsapp-bot
npm install
```

### 2. Configure Environment Variables
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```
Edit `.env` and set your free Gemini API key:
```env
GEMINI_API_KEY=your_gemini_api_key_here
```
*(Get a free Gemini API key at [Google AI Studio](https://aistudio.google.com/app/apikey))*

### 3. Start the Bot
```bash
npm start
```

### 4. Scan QR Code
1. A QR code will display directly in your terminal.
2. Open WhatsApp on your phone:
   - **Android**: Tap the 3 dots in the top right -> **Linked Devices** -> **Link a device**
   - **iOS**: Tap **Settings** -> **Linked Devices** -> **Link a device**
3. Point your camera at the terminal QR code to scan.
4. Your terminal will display:
   ```
   🚀 ✅ [Vektolux WhatsApp Bot] Connected successfully! Listening for messages...
   ```

---

## 💬 How It Works
- Any user who sends a WhatsApp message to your linked number will receive an instant AI response about:
  - Real Estate and Vehicle listings.
  - Escrow security (funds held safely in the Vektolux Escrow Wallet and released only after buyer inspection).
  - Mobile Money payments (Orange Money, Africell Afrimoney, QMoney via USSD).
  - Platform fees (minimal 1% escrow fee).
- Messages sent by you (`fromMe`) are automatically ignored so you can continue using your personal WhatsApp freely.
