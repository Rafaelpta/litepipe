import React, { useState } from "react";

/**
 * Extract the domain from a URL, stripping "www." prefix.
 * Handles URLs with or without protocol (e.g. "github.com/foo" or "https://github.com/foo").
 */
export function extractDomain(url: string): string | null {
	try {
		// Add protocol if missing — browser_url from screenpipe often lacks it
		const normalized = url.includes("://") ? url : `https://${url}`;
		const hostname = new URL(normalized).hostname;
		return hostname.replace(/^www\./, "") || null;
	} catch {
		return null;
	}
}

/**
 * Google Favicon API URL — uses gstatic directly to avoid 301 redirect.
 * Always fetches 64px for crisp rendering on retina displays.
 */
export function getFaviconUrl(domain: string): string {
	return `https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=http://${encodeURIComponent(domain)}&size=64`;
}

interface FaviconImgProps {
	domain: string;
	/** Fallback app name — used to build the app-icon URL on error */
	fallbackAppName?: string;
	size?: number;
	className?: string;
}

/**
 * Renders a website favicon with graceful fallback to the browser app icon.
 */
export function FaviconImg({ domain, fallbackAppName, size = 20, className }: FaviconImgProps) {
	const [errored, setErrored] = useState(false);

	if (errored && fallbackAppName) {
		return (
			// eslint-disable-next-line @next/next/no-img-element
			<img
				src={`http://localhost:11435/app-icon?name=${encodeURIComponent(fallbackAppName)}`}
				width={size}
				height={size}
				className={className ?? "rounded-sm object-contain"}
				alt={fallbackAppName}
				loading="lazy"
				decoding="async"
			/>
		);
	}

	return (
		// eslint-disable-next-line @next/next/no-img-element
		<img
			src={getFaviconUrl(domain)}
			width={size}
			height={size}
			className={className ?? "rounded-sm object-contain"}
			alt={domain}
			loading="lazy"
			decoding="async"
			onError={() => setErrored(true)}
		/>
	);
}
