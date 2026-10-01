const originalServe = Deno.serve;
(Deno as unknown as { serve: (handler: unknown) => void }).serve = () => {};
const { exportCSVs } = await import('../../supabase/functions/export-data/index.ts');
Deno.serve = originalServe;
console.log(JSON.stringify(exportCSVs(JSON.parse(await Deno.readTextFile(Deno.args[0])))));
