import React from 'react';
import { Card, CardHeader, CardContent } from './Card';

export function StatusCard({ title, status, description, icon, className = "" }) {
  const getStatusColor = () => {
    switch (status?.toLowerCase()) {
      case 'online':
      case 'active':
      case 'running':
      case 'enabled':
      case 'valid':
        return 'text-green-600 bg-green-50';
      case 'offline':
      case 'inactive':
      case 'stopped':
      case 'disabled':
      case 'invalid':
        return 'text-red-600 bg-red-50';
      case 'warning':
      case 'partial':
        return 'text-yellow-600 bg-yellow-50';
      default:
        return 'text-gray-600 bg-gray-50';
    }
  };

  const getIconColor = () => {
    switch (status?.toLowerCase()) {
      case 'online':
      case 'active':
      case 'running':
      case 'enabled':
      case 'valid':
        return 'text-green-500';
      case 'offline':
      case 'inactive':
      case 'stopped':
      case 'disabled':
      case 'invalid':
        return 'text-red-500';
      case 'warning':
      case 'partial':
        return 'text-yellow-500';
      default:
        return 'text-indigo-500';
    }
  };

  const [statusColor, bgColor] = getStatusColor().split(' ');

  return (
    <Card className={`transition-all duration-200 hover:shadow-md ${className}`}>
      <div className="flex items-center">
        {icon && (
          <div className={`${getIconColor()} mr-3 transition-colors duration-200`}>
            {icon}
          </div>
        )}
        <div className="flex-grow">
          <CardHeader className="flex items-center justify-between">
            <span>{title}</span>
            <span className={`ml-2 px-2.5 py-0.5 text-xs font-medium rounded-full ${getStatusColor()}`}>
              {status}
            </span>
          </CardHeader>
          {description && (
            <CardContent className="text-sm text-gray-600">
              {description}
            </CardContent>
          )}
        </div>
      </div>
    </Card>
  );
} 