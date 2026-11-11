import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { demoAPI } from '../services/demoAPI';
import { useDemoStatus } from '../hooks/useDemoStatus';

interface AutoLoopContextType {
  autoLoop: boolean;
  setAutoLoop: React.Dispatch<React.SetStateAction<boolean>>;
  toggleAutoLoop: () => void;
  isAnalyzing: boolean;
  pendingApprovalsCount: number;
  triggerCycleNow: () => Promise<void>;
  statusMessage: string;
}

const AutoLoopContext = createContext<AutoLoopContextType | undefined>(undefined);

export const AutoLoopProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [autoLoop, setAutoLoop] = useState<boolean>(() => {
    try {
      return localStorage.getItem('maiw_auto_loop') === 'true';
    } catch {
      return false;
    }
  });
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [statusMessage, setStatusMessage] = useState('Idle');
  const queryClient = useQueryClient();
  const { status: demoStatus } = useDemoStatus();

  // Save autoLoop state to localStorage so it stays persistent
  useEffect(() => {
    try {
      localStorage.setItem('maiw_auto_loop', String(autoLoop));
    } catch {}
  }, [autoLoop]);

  const toggleAutoLoop = useCallback(() => {
    setAutoLoop(prev => !prev);
  }, []);

  const pendingApprovalsCount = demoStatus?.pending_approvals?.length ?? 0;
  const scenarioActive = demoStatus?.active === true;

  const inFlightRef = useRef(false);

  const runAnalysisCycle = useCallback(async () => {
    if (inFlightRef.current) return;
    inFlightRef.current = true;
    setIsAnalyzing(true);
    setStatusMessage('Running multi-agent analysis...');
    try {
      await demoAPI.analyze();
      await queryClient.invalidateQueries({ queryKey: ['demo-status'] });
      setStatusMessage('Analysis complete.');
    } catch (err: any) {
      console.error('AutoLoop analysis error:', err);
      setStatusMessage('Analysis error (waiting for next tick)');
    } finally {
      setIsAnalyzing(false);
      inFlightRef.current = false;
    }
  }, [queryClient]);

  // Main continuous loop effect: runs continuously, pausing only when human approval is needed
  useEffect(() => {
    if (!autoLoop || !scenarioActive) {
      if (!autoLoop) setStatusMessage('Cyclic loop OFF');
      return;
    }

    // If there are pending approvals, pause and wait for human operator to click Approve
    if (pendingApprovalsCount > 0) {
      setStatusMessage(`Paused: Waiting for human approval on ${pendingApprovalsCount} action(s)`);
      return;
    }

    if (isAnalyzing || inFlightRef.current) {
      return;
    }

    // No pending approvals and not currently analyzing:
    // Once approval completes (or at initial start), automatically advance clock and run next cycle
    setStatusMessage('Next cycle starting in 2s...');
    const timer = setTimeout(async () => {
      if (!autoLoop || inFlightRef.current) return;
      try {
        // Advance clock by 60s so assigned workers complete in-progress tasks
        await demoAPI.tick(60);
        await queryClient.invalidateQueries({ queryKey: ['demo-status'] });
      } catch (e) {
        console.error('Tick error:', e);
      }
      runAnalysisCycle();
    }, 2000);

    return () => clearTimeout(timer);
  }, [autoLoop, scenarioActive, pendingApprovalsCount, isAnalyzing, runAnalysisCycle, queryClient]);

  return (
    <AutoLoopContext.Provider
      value={{
        autoLoop,
        setAutoLoop,
        toggleAutoLoop,
        isAnalyzing,
        pendingApprovalsCount,
        triggerCycleNow: runAnalysisCycle,
        statusMessage,
      }}
    >
      {children}
    </AutoLoopContext.Provider>
  );
};

export const useAutoLoop = (): AutoLoopContextType => {
  const ctx = useContext(AutoLoopContext);
  if (!ctx) {
    throw new Error('useAutoLoop must be used within an AutoLoopProvider');
  }
  return ctx;
};

