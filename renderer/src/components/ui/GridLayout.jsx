import React from 'react';

export function GridLayout({ children, className = "" }) {
  return (
    <div className={`grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3 ${className}`}>
      {children}
    </div>
  );
}

export function TwoColumnGrid({ children, className = "" }) {
  return (
    <div className={`grid gap-4 grid-cols-1 md:grid-cols-2 ${className}`}>
      {children}
    </div>
  );
} 