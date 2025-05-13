import React from 'react';

export function Card({ className = "", children }) {
  return (
    <div className={`p-4 rounded-2xl shadow-sm bg-white hover:shadow-md transition-shadow duration-300 ${className}`}>
      {children}
    </div>
  );
}

export function CardHeader({ className = "", children }) {
  return (
    <div className={`text-xl font-semibold text-gray-800 ${className}`}>
      {children}
    </div>
  );
}

export function CardContent({ className = "", children }) {
  return (
    <div className={`mt-3 ${className}`}>
      {children}
    </div>
  );
}

export function DataCard({ title, children, footer, className = "" }) {
  return (
    <Card className={className}>
      <CardHeader className="pb-2 mb-4 border-b border-gray-100">{title}</CardHeader>
      <CardContent>{children}</CardContent>
      {footer && <div className="mt-4 pt-3 border-t border-gray-100 text-sm text-gray-500">{footer}</div>}
    </Card>
  );
} 