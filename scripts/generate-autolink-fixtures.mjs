// 用网站实际的 Markdown 解析器（remark-parse + remark-gfm）生成裸网址的对照数据，
// BlogKit 的 LiteralAutolinkTests 逐条比较，保证 App 里的链接和网页上一致。
//
// 用法（在本仓库根目录，网站仓库已 bun install）：
//   node scripts/generate-autolink-fixtures.mjs ../mikexxz-blog > BlogKit/Tests/BlogKitTests/Fixtures/autolinks.json
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const blogRepo = resolve(process.argv[2] ?? "../mikexxz-blog");
const require = createRequire(join(blogRepo, "packages/shared/package.json"));
const load = async (name) => import(pathToFileURL(require.resolve(name)).href);
const { unified } = await load("unified");
const remarkParse = (await load("remark-parse")).default;
const remarkGfm = (await load("remark-gfm")).default;

const prefixes = ["", "x", "访问", " ", "(", "*", "[", "/", "😀", "a.", "“", "_"];
const cores = [
  "https://a.b/c",
  "http://example.com",
  "www.example.com",
  "www.",
  "me@a.example",
  "a_b@c.d1",
  "https://a.b/c_(d)",
  "www.a_b.c",
  "https://a.b/(x",
  "HTTPS://A.B",
  "WwW.a.b",
  "https://例子.测试/路径",
  "x.y+z@ex-ample.co.jp",
];
const suffixes = ["", ".", "。", "”。", ")", "&nbsp;", "]", "]x", "?!", "/x?y=1&z=2.", "_", "~", "<b", " 后", "é", "，然后"];

const cases = [];
for (const prefix of prefixes) for (const core of cores) for (const suffix of suffixes) cases.push(prefix + core + suffix);

const processor = unified().use(remarkParse).use(remarkGfm);
const textOf = (node) => (node.type === "text" || node.type === "inlineCode" ? node.value : (node.children ?? []).map(textOf).join(""));
const fixtures = cases.map((input) => {
  const links = [];
  const walk = (node) => {
    if (node.type === "link") links.push({ text: textOf(node), url: node.url });
    else (node.children ?? []).forEach(walk);
  };
  walk(processor.parse(input));
  return { input, links };
});
process.stdout.write(JSON.stringify(fixtures, null, 0).replaceAll("},{", "},\n{") + "\n");
