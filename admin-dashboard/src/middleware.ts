import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const ADMIN_COOKIE_NAME = "vx_admin_session";

export function middleware(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;

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

  // 2. Extract session token strictly from HttpOnly cookie (no header fallback)
  const cookieToken = request.cookies.get(ADMIN_COOKIE_NAME)?.value?.trim();
  const hasSession = Boolean(cookieToken);

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

  // 5. If already authenticated and accessing /login or /, redirect to /dashboard ONLY if not
  // arriving from an unauthenticated redirect (?from=) or carrying an error query.
  // This guarantees that an expired or invalid cookie will NEVER cause an infinite redirect loop.
  if (pathname === "/login" || pathname === "/") {
    const isRedirectedFromProtected = searchParams.has("from") || searchParams.has("error");
    if (hasSession && !isRedirectedFromProtected) {
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
