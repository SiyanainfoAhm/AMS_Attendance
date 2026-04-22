import { useMemo } from "react";

type Props = {
  page: number;
  pageSize: number;
  total: number;
  onPageChange: (page: number) => void;
  onPageSizeChange: (pageSize: number) => void;
  pageSizeOptions?: number[];
};

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function pageButtons(page: number, pageCount: number): Array<number | "…"> {
  if (pageCount <= 7) return Array.from({ length: pageCount }, (_, i) => i + 1);

  const out: Array<number | "…"> = [];
  const left = Math.max(2, page - 1);
  const right = Math.min(pageCount - 1, page + 1);

  out.push(1);
  if (left > 2) out.push("…");
  for (let p = left; p <= right; p++) out.push(p);
  if (right < pageCount - 1) out.push("…");
  out.push(pageCount);
  return out;
}

export function Pagination(props: Props) {
  const pageCount = useMemo(() => Math.max(1, Math.ceil(props.total / props.pageSize)), [props.total, props.pageSize]);
  const page = clamp(props.page, 1, pageCount);

  const buttons = useMemo(() => pageButtons(page, pageCount), [page, pageCount]);
  const canPrev = page > 1;
  const canNext = page < pageCount;

  return (
    <div className="pagination pagination-stacked">
      <div className="pager-top" role="navigation" aria-label="Pagination">
        <button type="button" className="pager-link" disabled={!canPrev} onClick={() => props.onPageChange(page - 1)}>
          Prev
        </button>
        <div className="pager-pages" aria-label="Page index">
          {buttons.map((b, i) =>
            b === "…" ? (
              <span key={`e-${i}`} className="pager-ellipsis" aria-hidden>
                …
              </span>
            ) : (
              <button
                key={b}
                type="button"
                className={`pager-page ${b === page ? "is-active" : ""}`}
                onClick={() => props.onPageChange(b)}
                aria-current={b === page ? "page" : undefined}
              >
                {b}
              </button>
            )
          )}
        </div>
        <button type="button" className="pager-link" disabled={!canNext} onClick={() => props.onPageChange(page + 1)}>
          Next
        </button>
      </div>

      <div className="pager-bottom">
        <div className="pager-right">
          <select
            className="select select-sm"
            value={props.pageSize}
            onChange={(e) => {
              const next = Math.max(1, Number(e.target.value) || props.pageSize);
              props.onPageSizeChange(next);
            }}
            aria-label="Items per page"
            title="Items per page"
          >
            {(props.pageSizeOptions ?? [10, 20, 25, 50, 100]).map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
          <span className="muted" style={{ marginLeft: "var(--space-2)" }}>
            items/page · {props.total} items
          </span>
        </div>
      </div>
    </div>
  );
}

