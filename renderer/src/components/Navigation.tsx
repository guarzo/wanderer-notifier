import React from 'react';
import { Link } from 'react-router-dom';
import { Drawer, List, ListItem, ListItemIcon, ListItemText } from '@mui/material';
import CompareIcon from '@mui/icons-material/Compare';
import BarChartIcon from '@mui/icons-material/BarChart';
import TimelineIcon from '@mui/icons-material/Timeline';

const Navigation: React.FC = () => {
  const menuItems = [
    {
      text: 'Kill Comparison',
      icon: <CompareIcon />,
      path: '/kill-comparison'
    },
    {
      text: 'Activity Charts',
      icon: <TimelineIcon />,
      path: '/charts'
    },
    {
      text: 'Kill Charts',
      icon: <BarChartIcon />,
      path: '/kill-charts'
    }
  ];

  return (
    <Drawer variant="permanent" anchor="left">
      <List>
        {menuItems.map((item) => (
          <ListItem 
            key={item.text} 
            component={Link} 
            to={item.path}
            sx={{ '&:hover': { backgroundColor: 'rgba(0, 0, 0, 0.04)' } }}
          >
            <ListItemIcon>{item.icon}</ListItemIcon>
            <ListItemText primary={item.text} />
          </ListItem>
        ))}
      </List>
    </Drawer>
  );
};

export default Navigation; 