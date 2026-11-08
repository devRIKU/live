# Lively — OpenAll

A local-first desktop assistant: streaming chat, generative UI, artifacts, tools, research and voice.

## The design system is the styling layer

The app is styled by the **Lively design system** in `../design-system/`, not by Tailwind.
The four stylesheets are copied verbatim into `src/styles/` so the app and the milestone
mockups in `../openall-mockups/` cannot drift:

| File | Owns |
| --- | --- |
| `src/styles/tokens.css` | Every value. One palette with two themes, resolved by `light-dark()`. |
| `src/styles/motion.css` | Every animation, and the reduced-motion policy. |
| `src/styles/shell.css` | The app chrome: sidebar, thread column, composer, popovers, settings. |
| `src/styles/surfaces.css` | What a milestone adds: artifact pane, permission card, terminal dock, research, voice, overlays. |
| `src/styles/app.css` | The few rules the app needs that the design system does not yet name. |

Component CSS may only reference semantic and component tokens. If a value is missing,
it goes in `tokens.css` first — never at the call site.

## The shell

| File | Owns |
| --- | --- |
| `src/app/App.tsx` | The shell: sidebar, conversation column, composer, surfaces. |
| `src/shell/Sidebar.tsx` | Conversation history and the account row. |
| `src/shell/Composer.tsx` | The input, tool menu, effort control, dictation and send. |
| `src/shell/ModelBar.tsx` | The model pill and provider status. |
| `src/shell/MessageTurn.tsx` | One message turn. |
| `src/shell/Icons.tsx` | The icon set — one shape language, drawn the same as the mockups. |
| `src/surfaces/` | One file per milestone surface. |

## Generative UI — OpenUI Lang 1.0

Model answers that are better shown as an interface are written in
[OpenUI Lang](https://www.openui.com) and rendered by
[`@openuidev/react-lang`](https://www.npmjs.com/package/@openuidev/react-lang).

| File | Purpose |
| --- | --- |
| `src/genui/schema.ts` | Zod schemas and the `LIMITS` table (rows, points, fields, children, text length). |
| `src/genui/library.ts` | The component library. **It is the allowlist** — a model can only emit components defined here. |
| `src/genui/components/` | One file per component (`Stack`, `Card`, `Text`, `Table`, `Chart`, `Form`, `Steps`, `Button`). |
| `src/genui/prompt.ts` | Builds the system prompt from the library, so the model is taught the exact components it may use. |
| `src/genui/split.ts` | Decides whether an answer is prose, a program, or prose around a program. |
| `src/genui/validate.ts` | Resource-bound checks; oversized collections are trimmed and reported. |
| `src/genui/OpenUIMessage.tsx` | Renders prose as markdown and programs with the OpenUI `<Renderer>`. |
| `src/genui/actions.ts` | Turns action events into host decisions (follow-up turn, safe link). |

To see it working, start the dev server and open
`http://localhost:5173/genui-preview.html` — that page renders hand-written
programs through the same code path the chat uses. To read the prompt the
model receives, run `npx tsx scripts/print-prompt.ts`.

Adding a component means adding it to `library.ts` and to the group list; the
prompt and the parser pick it up automatically.

## Checks

```bash
npm run build          # type-check and bundle
npm run lint           # oxlint
npx tsx tests/smoke_m4.ts   # generative UI
```

## License

MIT.
