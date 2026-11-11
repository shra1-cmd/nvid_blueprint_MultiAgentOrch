import React, { useState } from 'react';
import { Box, Typography, Drawer, IconButton } from '@mui/material';
import { Menu as MenuIcon } from '@mui/icons-material';
import { useNavigate, useLocation } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import { healthAPI } from '../services/api';
import { useDemoStatus } from '../hooks/useDemoStatus';
import { useAutoLoop } from '../context/AutoLoopContext';
import StatusBar from './StatusBar';

interface LayoutProps {
  children: React.ReactNode;
}

const NAV = [
  { label: 'OPERATIONS', path: '/demo' },        // Primary operator surface
  { label: 'WORLD', path: '/world' },
  { label: 'RELIABILITY', path: '/command' },    // Governance & system overview
  { label: 'MODELS', path: '/models' },
  { label: 'CAPABILITIES', path: '/capabilities' },
  { label: 'ACTIVITY', path: '/activity' },
  { label: 'DEPLOYMENT', path: '/deployment' },  // Platform/Security: sandbox, model policy, auth
];

const WAREHOUSE_ID = process.env.REACT_APP_WAREHOUSE_ID || 'DC-47';

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  const { data: live } = useQuery({
    queryKey: ['live'],
    queryFn: healthAPI.getLive,
    refetchInterval: 15000,
    retry: 0,
    staleTime: 10000,
  });
  const isLive = live?.status === 'alive';

  // Demo mode detection — threaded from backend status so all pages show the indicator
  const { isDemoMode } = useDemoStatus();
  const { autoLoop, toggleAutoLoop, isAnalyzing, pendingApprovalsCount, statusMessage } = useAutoLoop();

  const NavItems = () => (
    <>
      {NAV.map(({ label, path }) => {
        const active = location.pathname.startsWith(path);
        return (
          <Box
            key={path}
            onClick={() => { navigate(path); setMobileOpen(false); }}
            sx={{
              px: { xs: 1.5, md: 1.25, xl: 1.75 },
              py: 0.5,
              display: 'flex',
              alignItems: 'center',
              cursor: 'pointer',
              position: 'relative',
              color: active ? '#E6EDF3' : '#484F58',
              fontFamily: 'monospace',
              fontWeight: active ? 700 : 500,
              fontSize: '0.72rem',
              letterSpacing: '0.05em',
              textTransform: 'uppercase',
              whiteSpace: 'nowrap',
              transition: 'color 0.15s',
              '&:hover': { color: active ? '#E6EDF3' : '#8B949E' },
              '&::after': active ? {
                content: '""',
                position: 'absolute',
                bottom: 0,
                left: 0,
                right: 0,
                height: '2px',
                backgroundColor: '#76B900',
              } : {},
            }}
          >
            {label}
          </Box>
        );
      })}
    </>
  );

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: '100vh', width: '100%', backgroundColor: '#080C10', overflow: 'hidden' }}>

      {/* Top bar */}
      <Box
        sx={{
          height: 48,
          minHeight: 48,
          display: 'flex',
          alignItems: 'stretch',
          borderBottom: '1px solid #1C2128',
          backgroundColor: '#0D1117',
          flexShrink: 0,
          px: 2,
          gap: 0,
        }}
      >
        {/* Brand */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, pr: 3, borderRight: '1px solid #1C2128', mr: 2, flexShrink: 0 }}>
          <Box
            component="img"
            src="/nvidia-logo.svg"
            alt="NVIDIA"
            sx={{ height: 16, width: 'auto' }}
            onError={(e: any) => { e.target.style.display = 'none'; }}
          />
          <Typography component="h1" sx={{ fontFamily: 'monospace', fontWeight: 700, fontSize: '0.75rem', color: '#E6EDF3', letterSpacing: '0.04em', whiteSpace: 'nowrap' }}>
            MAIW OPERATIONS
          </Typography>
        </Box>

        {/* LIVE indicator */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, pr: 2.5, borderRight: '1px solid #1C2128', mr: 2, flexShrink: 0 }}>
          <Box sx={{
            width: 7, height: 7, borderRadius: '50%',
            backgroundColor: isLive ? '#3FB950' : '#484F58',
            boxShadow: isLive ? '0 0 6px #3FB950' : 'none',
            animation: isLive ? 'livePulse 2s ease-in-out infinite' : 'none',
            '@keyframes livePulse': { '0%,100%': { opacity: 1 }, '50%': { opacity: 0.5 } },
          }} />
          <Typography sx={{ fontFamily: 'monospace', fontSize: '0.67rem', fontWeight: 700, color: isLive ? '#3FB950' : '#484F58', letterSpacing: '0.06em' }}>
            {isLive ? 'LIVE' : 'OFFLINE'}
          </Typography>
        </Box>

        {/* Warehouse ID */}
        <Box sx={{ display: { xs: 'none', xl: 'flex' }, alignItems: 'center', pr: 2.5, borderRight: '1px solid #1C2128', mr: 2, flexShrink: 0 }}>
          <Typography sx={{ fontFamily: 'monospace', fontSize: '0.67rem', color: '#8B949E', letterSpacing: '0.04em', whiteSpace: 'nowrap' }}>
            WAREHOUSE: <Box component="span" sx={{ color: '#C9D1D9', fontWeight: 700 }}>{WAREHOUSE_ID}</Box>
          </Typography>
        </Box>

        {/* Demo mode indicator — visible across all pages during synthetic warehouse sessions */}
        {isDemoMode && (
          <Box
            data-testid="demo-mode-indicator"
            sx={{
              display: { xs: 'none', sm: 'flex' },
              alignItems: 'center',
              px: 1.25, py: 0,
              mr: 2,
              borderRight: '1px solid #1C2128',
              flexShrink: 0,
            }}
          >
            <Box sx={{
              background: '#0d2146',
              border: '1px solid #1F3458',
              borderRadius: '3px',
              px: '6px', py: '2px',
              fontFamily: 'monospace', fontSize: '0.6rem',
              color: '#58A6FF', letterSpacing: '0.08em',
              textTransform: 'uppercase',
              whiteSpace: 'nowrap',
            }}>
              SIMULATED WAREHOUSE
            </Box>
          </Box>
        )}

        {/* Desktop nav — scrolls sideways rather than cutting off items on narrow windows */}
        <Box
          data-testid="desktop-nav"
          sx={{
            display: { xs: 'none', lg: 'flex' },
            alignItems: 'stretch',
            gap: 0,
            minWidth: 0,
            overflowX: 'auto',
            scrollbarWidth: 'none',
            '&::-webkit-scrollbar': { display: 'none' },
          }}
        >
          <NavItems />
          {/* Cyclic loop button right beside DEPLOYMENT tab */}
          <Box sx={{ display: 'flex', alignItems: 'center', ml: 1.5, mr: 1 }}>
            <Box
              component="button"
              onClick={toggleAutoLoop}
              data-testid="main-top-cyclic-loop-toggle"
              title={
                autoLoop
                  ? `Cyclic Loop is ON (${statusMessage}). Click to turn OFF.`
                  : 'Turn ON Cyclic Loop: Runs continuously and automatically triggers next cycle after each approval.'
              }
              sx={{
                display: 'flex',
                alignItems: 'center',
                gap: 0.75,
                background: autoLoop ? '#2d1f05' : '#161B22',
                border: `1px solid ${autoLoop ? '#D29922' : '#30363D'}`,
                borderRadius: '4px',
                px: 1.25,
                py: '4px',
                fontFamily: 'monospace',
                fontSize: '0.68rem',
                fontWeight: 700,
                color: autoLoop ? '#E3B341' : '#8B949E',
                cursor: 'pointer',
                letterSpacing: '0.05em',
                textTransform: 'uppercase',
                transition: 'all 0.15s ease',
                '&:hover': {
                  color: autoLoop ? '#E3B341' : '#C9D1D9',
                  borderColor: autoLoop ? '#D29922' : '#76B900',
                  background: autoLoop ? '#3d2907' : '#1C2128',
                },
              }}
            >
              <Box
                sx={{
                  width: 7,
                  height: 7,
                  borderRadius: '50%',
                  background: autoLoop ? '#E3B341' : '#484F58',
                  boxShadow: autoLoop ? '0 0 6px #E3B341' : 'none',
                  animation: autoLoop && isAnalyzing ? 'pulse 1.5s infinite' : 'none',
                  flexShrink: 0,
                }}
              />
              CYCLIC LOOP: {autoLoop ? 'ON' : 'OFF'}
              {autoLoop && pendingApprovalsCount > 0 && (
                <Box
                  component="span"
                  sx={{
                    ml: 0.75,
                    px: '5px',
                    py: '1px',
                    borderRadius: '3px',
                    background: '#F8514933',
                    border: '1px solid #F85149',
                    color: '#F85149',
                    fontSize: '0.6rem',
                  }}
                >
                  PAUSED FOR APPROVAL
                </Box>
              )}
            </Box>
          </Box>
        </Box>

        {/* Right spacer + mobile hamburger */}
        <Box sx={{ flexGrow: 1 }} />
        <IconButton
          onClick={() => setMobileOpen(true)}
          sx={{ display: { lg: 'none' }, color: '#484F58', p: 0.5 }}
          size="small"
        >
          <MenuIcon sx={{ fontSize: 18 }} />
        </IconButton>
      </Box>

      {/* Mobile nav drawer */}
      <Drawer
        open={mobileOpen}
        onClose={() => setMobileOpen(false)}
        sx={{ '& .MuiDrawer-paper': { backgroundColor: '#0D1117', borderRight: '1px solid #1C2128', width: 200, pt: 2 } }}
      >
        <Box sx={{ display: 'flex', flexDirection: 'column' }}>
          <NavItems />
        </Box>
      </Drawer>

      {/* Content — scrolls when a page is taller than the window; pages with
          their own scroll regions (height: 100%) fill it and scroll inside. */}
      <Box
        data-testid="layout-content"
        sx={{
          flex: 1,
          minHeight: 0,
          overflow: 'auto',
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        {children}
      </Box>

      <StatusBar />
    </Box>
  );
};

export default Layout;
