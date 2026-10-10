import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const ADMIN_COOKIE_NAME = "vx_admin_session";
const SESSION_HEADER = "x-vektolux-session";

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // 1. Allow public auth endpoints and static assets
  if (
    pathname === "/api/auth/login" ||
    pathname === "/robots.txt" ||
    pathname.startsWith("/_next") ||
    pathname.startsWith("/images") ||
    pathname.startsWith("/favicon")
  ) {
    return NextResponse.next();
  }

  // 2. Extract session token from cookie (primary) or header (fallback)
  const cookieToken = request.cookies.get(ADMIN_COOKIE_NAME)?.value?.trim();
  const headerToken = request.headers.get(SESSION_HEADER)?.trim();
  const hasSession = Boolean(cookieToken || headerToken);

  // 3. API route protection: return 401 JSON if unauthenticated
  if (pathname.startsWith("/api/")) {
    if (!hasSession) {
      return NextResponse.json(
        {
          success: false,
          error: "Unauthorized: Administrator session required.",
          code: "UNAUTHORIZED",
        },
        { status: 401 }
      );
    }
    return NextResponse.next();
  }

  // 4. Dashboard page protection: redirect to /login if unauthenticated
  if (pathname.startsWith("/dashboard")) {
    if (!hasSession) {
      const loginUrl = new URL("/login", request.url);
      loginUrl.searchParams.set("from", pathname);
      return NextResponse.redirect(loginUrl);
    }
    return NextResponse.next();
  }

  // 5. If already authenticated and accessing /login or /, redirect to /dashboard
  if (pathname === "/login" || pathname === "/") {
    if (hasSession) {
      return NextResponse.redirect(new URL("/dashboard", request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/dashboard/:path*",
    "/api/:path*",
    "/login",
    "/",
  ],
};
