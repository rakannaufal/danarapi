export {};
declare global {
  var DanarapiCalculatorEngine: {
    visible(field: { visible?: Record<string, string | string[]> }, values: Record<string, string>): boolean;
    calculate(catalog: unknown, id: string, input: Record<string, string>): unknown;
    calculateJSON(catalog: string, id: string, input: string): string;
  };
}
