import type { Metadata } from 'next';
import { Fragment, type ReactNode } from 'react';
import Link from 'next/link';
import { ArrowLeft, ArrowUpRight, BookOpen, Bot, Download } from 'lucide-react';
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table';
import data from '@/lib/actuators.json';
import './reference.css';

export const metadata: Metadata = {
  title: 'B601-DM Actuator Settings · Motion Lab',
  description:
    'B601-DM actuator reference: per-joint defaults, command modes, 53 Damiao registers, units, explanations, and source-specific caveats.',
};
const sources = Object.fromEntries(
  data.sources.map((source) => [source.id, source]),
);
const sectionLinks = [
  ['overview', 'Read first'],
  ['assignments', 'Motor assignments'],
  ['gains', 'Per-joint gains'],
  ['modes', 'Control modes'],
  ['commands', 'Live commands'],
  ['software', 'Software settings'],
  ['registers', 'Firmware registers'],
  ['model-limits', 'Simulator limits'],
  ['operations', 'Maintenance'],
  ['feedback', 'Feedback & status'],
  ['sources', 'Sources'],
];
function SourceLinks({ ids }: { ids: string[] }) {
  return (
    <p className="ref-sources">
      Sources:{' '}
      {ids.map((id, i) => (
        <span key={id}>
          {i > 0 ? ' · ' : ''}
          <a href={sources[id].url} target="_blank" rel="noreferrer">
            {sources[id].title}
            <ArrowUpRight />
          </a>
        </span>
      ))}
    </p>
  );
}
function Section({
  id,
  title,
  children,
  sourceIds = [],
}: {
  id: string;
  title: string;
  children: ReactNode;
  sourceIds?: string[];
}) {
  return (
    <section id={id} className="ref-section">
      <h2>{title}</h2>
      {children}
      {sourceIds.length > 0 && <SourceLinks ids={sourceIds} />}
    </section>
  );
}
function DataTable({
  headers,
  rows,
  label,
}: {
  headers: string[];
  rows: ReactNode[][];
  label: string;
}) {
  return (
    <div
      className="ref-table-wrap"
      aria-label={label + '; scroll horizontally on narrow screens'}
    >
      <Table aria-label={label}>
        <TableHeader>
          <TableRow>
            {headers.map((h) => (
              <TableHead key={h} scope="col">
                {h}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row, i) => (
            <TableRow key={i}>
              {row.map((c, j) => (
                <TableCell key={j}>{c}</TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
export default function ActuatorReference() {
  const rw = data.registers.filter((r) => r.access === 'RW').length;
  return (
    <main className="app-shell reference-shell">
      <header className="topbar">
        <Link href="/" className="brand ref-brand">
          <div className="brand-mark">
            <Bot />
          </div>
          <strong>
            reBot <span>/ Motion Lab</span>
          </strong>
        </Link>
        <Link className="secondary" href="/">
          <ArrowLeft />
          Simulator
        </Link>
      </header>
      <div className="ref-heading">
        <div>
          <div className="eyebrow">B601-DM · Reference</div>
          <h1>Actuator settings</h1>
          <p>
            What each setting means, where it lives, and which published values
            apply.
          </p>
        </div>
        <a className="primary" href="/B601-DM-actuator-settings.md" download>
          <Download />
          Download reference
        </a>
      </div>
      <div className="ref-layout">
        <nav className="ref-nav" aria-label="Reference sections">
          <span className="eyebrow">On this page</span>
          {sectionLinks.map(([id, label]) => (
            <a href={'#' + id} key={id}>
              {label}
            </a>
          ))}
          <div className="ref-nav-note">
            <BookOpen />
            <span>
              Source snapshot
              <br />
              {data.checked}
              <br />
              Read-only reference
            </span>
          </div>
        </nav>
        <article className="ref-content">
          <Section id="overview" title="Read first">
            <p>
              This reference covers the seven actuators in the published B601-DM
              configuration and every register in the inspected MotorBridge
              Damiao table. Values shown here are documented defaults and
              definitions; no actuator has been queried.
            </p>
            <div className="ref-counts">
              <div>
                <strong>7</strong>
                <span>Actuators</span>
              </div>
              <div>
                <strong>{data.registers.length}</strong>
                <span>Known registers</span>
              </div>
              <div>
                <strong>
                  {rw} / {data.registers.length - rw}
                </strong>
                <span>Read-write / read-only</span>
              </div>
            </div>
            {data.notes.slice(1).map((n, i) => (
              <div
                key={n.title}
                className={'ref-note ' + (i === 0 ? 'ref-discrepancy' : '')}
              >
                <h3>{n.title}</h3>
                <p>{n.text}</p>
                {n.sources && <SourceLinks ids={n.sources} />}
              </div>
            ))}
          </Section>
          <Section
            id="assignments"
            title="Motor assignments & encoding scales"
            sourceIds={['sdk-config', 'models']}
          >
            <p>
              The motor names and IDs come from Seeed’s configuration. The three
              mapping magnitudes come from MotorBridge’s model catalog. They are
              not device readbacks or continuous torque ratings.
            </p>
            <DataTable
              label="Actuator assignments"
              headers={[
                'Joint',
                'Motor',
                'Receive ID',
                'Feedback ID',
                'PMAX · rad',
                'VMAX · rad/s',
                'TMAX · N·m',
              ]}
              rows={data.actuators.map((a) => [
                <code key="code-0">{a.joint}</code>,
                a.model,
                <code key="code-1">{a.motor_id}</code>,
                <code key="code-2">{a.feedback_id}</code>,
                a.pmax,
                a.vmax,
                a.tmax,
              ])}
            />
          </Section>
          <Section
            id="gains"
            title="Published per-joint gains"
            sourceIds={['sdk-config', 'sdk-code', 'protocol']}
          >
            <p>
              MIT kp uses N·m/rad and kd uses N·m·s/rad. Position/velocity gains
              have firmware-specific scaling; vlim is in rad/s. These values
              reproduce the published YAML, including its kd mismatch.
            </p>
            <DataTable
              label="Per-joint gain defaults"
              headers={[
                'Joint',
                'MIT kp',
                'MIT kd',
                'Velocity kp',
                'Velocity ki',
                'Position kp',
                'Position ki',
                'vlim',
              ]}
              rows={data.actuators.map((a) => [
                <code key="code-3">{a.joint}</code>,
                a.kp,
                a.kd > 5 ? (
                  <span key="clamped-damping" className="ref-flag">
                    {a.kd} → clipped to 5*
                  </span>
                ) : (
                  a.kd
                ),
                a.vel_kp,
                a.vel_ki,
                a.pos_kp,
                a.pos_ki,
                a.vlim,
              ])}
            />
            <p className="ref-small">
              * With the inspected MotorBridge encoder. The installed SDK
              version and motor firmware have not been verified.
            </p>
          </Section>
          <Section
            id="modes"
            title="Control modes"
            sourceIds={['protocol', 'manual']}
          >
            <DataTable
              label="Control modes"
              headers={['Code', 'Mode', 'CAN command ID', 'What it does']}
              rows={data.modes.map((m) => [
                m.code,
                m.name,
                <code key="code-4">{m.offset}</code>,
                m.description,
              ])}
            />
            <div className="ref-equation">
              <span className="eyebrow">Conceptual MIT control law</span>
              <p className="mono">
                τ = kp × (p_des − p) + kd × (v_des − v) + τ_ff
              </p>
              <span>
                Restoring torque + damping torque + feedforward torque. Firmware
                limiting and motor conversion also apply.
              </span>
            </div>
          </Section>
          <Section
            id="commands"
            title="Live command fields"
            sourceIds={['protocol', 'sdk-code']}
          >
            <p>
              These values travel in motion commands. Packet ranges describe
              what can be encoded; they do not establish a suitable operating
              range for the arm.
            </p>
            <DataTable
              label="Live command fields"
              headers={[
                'Command field',
                'Range / format',
                'Unit',
                'What it does',
              ]}
              rows={data.commands.map((c) => [
                <code key="code-5">{c.key}</code>,
                c.range,
                c.unit,
                c.description,
              ])}
            />
          </Section>
          <Section
            id="software"
            title="Software settings & gravity compensation"
            sourceIds={['sdk-config', 'sdk-code', 'gravity', 'setup']}
          >
            <p>
              All fields from Seeed’s B601-DM YAML are represented below,
              followed by related SDK controls. YAML defaults and Python
              constructor defaults are distinguished where they differ.
            </p>
            <DataTable
              label="Software actuator settings"
              headers={[
                'Setting',
                'Published value / API default',
                'Unit',
                'What it does',
              ]}
              rows={data.software.map((s) => [
                <code key="code-6">{s.key}</code>,
                s.value,
                s.unit,
                <Fragment key="fragment-0">
                  {s.description}
                  <a
                    className="ref-row-source"
                    href={sources[s.source].url}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Source <ArrowUpRight />
                  </a>
                </Fragment>,
              ])}
            />
          </Section>
          <Section
            id="registers"
            title="Complete firmware register catalog"
            sourceIds={['registers', 'manual']}
          >
            <p>
              <b>RW</b> means writable through the documented interface;{' '}
              <b>RO</b> means read-only in the inspected driver.{' '}
              <code key="code-7">float32</code> is a 32-bit floating-point
              value; <code key="code-8">uint32</code> is an unsigned 32-bit
              integer. The broad declared ranges are protocol constraints, not
              recommended settings. Current device values are unknown.
            </p>
            <p className="ref-small">
              Register numbers are decimal. Gaps are unlisted. “Extended” marks
              entries absent from common older tables; support depends on the
              installed firmware. Unspecified units and coefficient behavior
              have not been inferred.
            </p>
            {data.categories.map((category) => (
              <div className="ref-register-group" key={category}>
                <h3>{category}</h3>
                <DataTable
                  label={category + ' registers'}
                  headers={[
                    'RID / register',
                    'Access / type',
                    'Declared range / unit',
                    'What it does',
                  ]}
                  rows={data.registers
                    .filter((r) => r.category === category)
                    .map((r) => [
                      <Fragment key="fragment-1">
                        <span className="ref-rid mono">{r.rid}</span>
                        <code key="code-9">{r.name}</code>
                        {r.extended && (
                          <span className="ref-extended">Extended</span>
                        )}
                      </Fragment>,
                      <Fragment key="fragment-2">
                        <span
                          className={'ref-access ' + r.access.toLowerCase()}
                        >
                          {r.access}
                        </span>
                        <small>{r.type}</small>
                      </Fragment>,
                      <Fragment key="fragment-3">
                        <code key="code-10">{r.range}</code>
                        <small>{r.unit}</small>
                      </Fragment>,
                      r.description,
                    ])}
                />
              </div>
            ))}
          </Section>
          <Section
            id="model-limits"
            title="Simulator model limits"
            sourceIds={['model']}
          >
            <p>
              The simulator enforces URDF lower and upper travel bounds. Effort
              and velocity fields below are declarations from the robot model;
              this kinematic simulator does not apply a torque model. They are
              distinct from the actuator’s mapping scales.
            </p>
            <DataTable
              label="URDF limits"
              headers={[
                'Joint',
                'Lower · rad',
                'Upper · rad',
                'Effort · N·m',
                'Velocity · rad/s',
              ]}
              rows={data.actuators
                .filter((a) => a.lower !== null)
                .map((a) => [
                  <code key="code-11">{a.joint}</code>,
                  a.lower,
                  a.upper,
                  a.urdf_effort,
                  a.urdf_velocity,
                ])}
            />
            <p>
              The gripper UI spans 0–90 mm nominal opening. The source finger
              joints allow 0 to +0.05 m and −0.05 to 0 m. Those prismatic
              travels are not the physical motor’s angle; motor 7 drives both
              fingers through the mechanism.
            </p>
          </Section>
          <Section
            id="operations"
            title="Maintenance & persistence"
            sourceIds={['manual', 'protocol']}
          >
            <DataTable
              label="Maintenance operations"
              headers={['Operation', 'What it does', 'Persistence']}
              rows={data.operations.map((o) => [
                o.name,
                o.description,
                o.persistence,
              ])}
            />
          </Section>
          <Section
            id="feedback"
            title="Feedback & status"
            sourceIds={['protocol', 'manual']}
          >
            <p>
              Standard feedback reports position in rad, velocity in rad/s,
              torque in N·m, MOS and winding temperatures in °C, and a status
              code. Position, velocity and torque decoding depends on matching
              PMAX, VMAX and TMAX. Temperature telemetry is separate from
              writable temperature thresholds.
            </p>
            <DataTable
              label="Motor status codes"
              headers={['Status code', 'Meaning']}
              rows={data.statuses.map(([code, name]) => [
                <code key="code-12">{code}</code>,
                name,
              ])}
            />
          </Section>
          <Section id="sources" title="Sources & version scope">
            <p>
              Repository links are pinned to the inspected commits. The older
              manufacturer manual and the current driver differ in places; those
              differences remain visible instead of being merged into an assumed
              universal configuration.
            </p>
            <ol className="ref-source-list">
              {data.sources.map((s) => (
                <li key={s.id}>
                  <a href={s.url} target="_blank" rel="noreferrer">
                    {s.title}
                    <ArrowUpRight />
                  </a>
                  <p>{s.detail}</p>
                </li>
              ))}
            </ol>
            <p className="ref-small">
              Register metadata: © 2026 motorbridge, MIT license.{' '}
              <a
                href="/actuator-reference/MOTORBRIDGE-LICENSE.txt"
                target="_blank"
                rel="noreferrer"
              >
                Read license
              </a>
              . Explanations are authored for this reference.
            </p>
          </Section>
        </article>
      </div>
    </main>
  );
}
