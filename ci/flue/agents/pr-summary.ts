import { defineAgent } from '@flue/runtime';

// PR 摘要 agent。Jenkins 在 MR test 通過後呼叫：
//   GEMINI_API_KEY=... flue run pr-summary --input '{"message": "<git diff>"}'
// stdout 為單行 JSON（{"text": "...摘要...", ...}），stderr 為裝飾性輸出。
export default defineAgent(() => ({
	model: 'google/gemini-2.5-flash',
	instructions: [
		'你是資深 DevOps 工程師，請根據使用者提供的 git diff，用繁體中文撰寫 PR 審查摘要。',
		'嚴格限制全文 100 字以內，不使用 emoji，精簡扼要。',
		'格式：',
		'### 變更摘要',
		'（一句話概述）',
		'### 主要異動',
		'（條列，最多 3 點，每點一行）',
		'### 需注意',
		'（潛在風險一句；若無寫「無特殊風險」）',
	].join('\n'),
}));
