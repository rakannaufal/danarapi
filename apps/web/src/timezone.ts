export function fromZonedTime(day: string, timezone: string) {
  const target = Date.parse(`${day}T00:00:00Z`);
  let candidate = target;
  for (let iteration = 0; iteration < 3; iteration++) {
    const parts = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(candidate));
    const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
    const displayed = Date.parse(`${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}:${values.second}Z`);
    candidate += target - displayed;
  }
  return new Date(candidate).toISOString();
}
