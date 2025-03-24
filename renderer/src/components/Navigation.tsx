import React from 'react';
import { Link } from 'react-router-dom';
import { Drawer, List, ListItem, ListItemIcon, ListItemText, Typography } from '@mui/material';
import CompareIcon from '@mui/icons-material/Compare';

const Navigation: React.FC = () => {
  const menuItems = [
    {
      text: 'Kill Comparison',
      icon: <CompareIcon />,
      path: '/kill-comparison'
    },
  ];

  return (
    <Drawer variant="permanent" anchor="left">
      <List>
        {menuItems.map((item) => (
          <ListItem button key={item.text} component={Link} to={item.path}>
            <ListItemIcon>{item.icon}</ListItemIcon>
            <ListItemText primary={item.text} />
          </ListItem>
        ))}
      </List>
    </Drawer>
  );
};

export default Navigation; 