import { Link } from 'react-router-dom';
import { EmptyState } from '../components/QueryState';
import { PageHeader } from '../components/ui';

export default function NotFound() {
  return (
    <>
      <PageHeader title="Page not found" />
      <EmptyState>
        There’s nothing at this address.{' '}
        <Link to="/" className="font-medium text-accent underline underline-offset-2">
          Go to the dashboard
        </Link>
      </EmptyState>
    </>
  );
}
