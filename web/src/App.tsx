import { lazy, Suspense } from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { configError } from './lib/supabase';
import { AuthProvider, useAuth } from './hooks/useAuth';
import { Layout } from './components/Layout';
import { LoadingState } from './components/QueryState';
import Login from './pages/Login';
import SetupError from './pages/SetupError';

const Dashboard = lazy(() => import('./pages/Dashboard'));
const Transactions = lazy(() => import('./pages/Transactions'));
const Bills = lazy(() => import('./pages/Bills'));
const Paychecks = lazy(() => import('./pages/Paychecks'));
const Spending = lazy(() => import('./pages/Spending'));
const Debts = lazy(() => import('./pages/Debts'));
const Envelopes = lazy(() => import('./pages/Envelopes'));
const NotFound = lazy(() => import('./pages/NotFound'));

function Splash() {
  return (
    <div className="grid min-h-dvh place-items-center bg-bg" role="status" aria-live="polite">
      <span className="text-sm text-muted">Loading Money Hub…</span>
    </div>
  );
}

function Gate() {
  const { session, initializing } = useAuth();
  if (initializing) return <Splash />;
  if (!session) return <Login />;
  return (
    <Routes>
      <Route element={<Layout />}>
        {(
          [
            ['/', Dashboard],
            ['/transactions', Transactions],
            ['/bills', Bills],
            ['/paychecks', Paychecks],
            ['/spending', Spending],
            ['/debts', Debts],
            ['/envelopes', Envelopes],
            ['*', NotFound],
          ] as const
        ).map(([path, Page]) => (
          <Route
            key={path}
            path={path}
            element={
              <Suspense fallback={<LoadingState label="page" lines={6} />}>
                <Page />
              </Suspense>
            }
          />
        ))}
      </Route>
    </Routes>
  );
}

export default function App() {
  if (configError) return <SetupError message={configError} />;
  return (
    <AuthProvider>
      <BrowserRouter>
        <Gate />
      </BrowserRouter>
    </AuthProvider>
  );
}
