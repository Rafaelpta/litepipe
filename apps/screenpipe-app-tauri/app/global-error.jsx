"use client";

import Error from "next/error";
import { useEffect } from "react";

export default function GlobalError({ error }) {
    useEffect(() => {
        console.error("Global error boundary caught:", error?.message, error?.stack);
    }, [error]);

    return (
        <html>
            <body>
                <Error />
            </body>
        </html>
    );
}
