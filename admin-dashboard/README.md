# Vektolux Admin Dashboard

Local admin web dashboard for Vektolux platform management.
Connects directly to the live Convex production backend.

## Getting Started

```bash
cd admin-dashboard
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Login Credentials

- **Email**: `admin@vektolux.sl`
- **Password**: `password123`

## Features

- **Verification Queue**: Review and approve/reject agent & merchant applications in real-time
- **Listings Inspector**: View all properties and vehicles, filter by type, clear all data
- **Quick Seed**: 1-click test data injection across Freetown, Bo, Makeni, Waterloo
- **Live Backend**: Connected to `https://incredible-possum-462.convex.cloud` (production)

## Architecture

- Next.js 14 App Router
- Calls Convex backend via `ConvexHttpClient` in API routes (server-side)
- Admin session stored in `sessionStorage` (cleared on browser close)
- No database of its own — 100% connected to Convex

## Security

This dashboard is designed for **local use only**. Never expose port 3000 to the internet.
The admin credentials are verified against the live Convex `users` table.
