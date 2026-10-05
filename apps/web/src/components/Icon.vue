<script setup lang="ts">
import type { Component } from 'vue';
import { House, ArrowRightLeft, Scan, ChartSpline, Settings, Plus, ArrowUp, ArrowDown, WalletMinimal, ChevronRight, X, UsersRound, Upload, Eye, EyeOff, Sun, Moon, Trash2, SquarePen, Download, Check, RefreshCw, Search, CircleAlert, FileText, ArrowLeft, Copy, Menu, Ellipsis, UtensilsCrossed, CarFront, ShoppingBasket, Landmark, Bell, CircleHelp, Goal, ChartPie, CalendarDays, Camera, Images, QrCode, LogOut, Tag, Calculator, Star, History, Info, Share2 } from '@lucide/vue';
defineProps<{ name: string; size?: number }>();
const icons: Record<string, Component> = {
  calculator: Calculator, star: Star, history: History, info: Info, share: Share2,
  tag: Tag, house: House, chart: ChartSpline, people: UsersRound,
  home: House, transactions: ArrowRightLeft, review: Scan, reports: ChartSpline,
  settings: Settings, target: Goal, budget: ChartPie, calendar: CalendarDays,
  income: ArrowDown, expense: ArrowUp, transfer: ArrowRightLeft, split: UsersRound,
  wallet: WalletMinimal, bank: Landmark, category: Tag,
  food: UtensilsCrossed, transport: CarFront, household: ShoppingBasket,
  plus: Plus, next: ChevronRight, close: X, back: ArrowLeft, menu: Menu, more: Ellipsis,
  upload: Upload, download: Download, camera: Camera, gallery: Images, qris: QrCode,
  eye: Eye, hidden: EyeOff, sun: Sun, moon: Moon, trash: Trash2, edit: SquarePen,
  check: Check, reset: RefreshCw, search: Search, warning: CircleAlert, file: FileText,
  copy: Copy, bell: Bell, help: CircleHelp, logout: LogOut,
  Target: Goal, ChartPie, CalendarDays,
};
</script>
<template><component :is="icons[name] ?? icons.category" :size="size ?? 20" :stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" /></template>
