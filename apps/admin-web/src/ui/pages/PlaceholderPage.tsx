import { Layout } from "../components/Layout";

export function PlaceholderPage({ title }: { title: string }) {
  return (
    <Layout>
      <div className="page-stack">
        <div className="card card-elevated">
          <h1 className="page-title mt-0">{title}</h1>
          <p className="page-subtitle" style={{ marginTop: "var(--space-2)" }}>
            This section is scaffolded. Wire it to an Edge Function when you are ready to ship the feature.
          </p>
        </div>
      </div>
    </Layout>
  );
}
