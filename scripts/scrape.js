const { chromium } = require('playwright');

async function scrapeGitHubTrending() {
  const browser = await chromium.launch({ 
    headless: true,
    channel: 'chrome',
    args: ['--ignore-certificate-errors']
  });
  
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: 1920, height: 1080 }
  });
  
  const page = await context.newPage();
  
  console.log('📡 正在访问 GitHub Trending...');
  
  await page.goto('https://github.com/trending', { 
    waitUntil: 'domcontentloaded',
    timeout: 45000 
  });
  
  // 等待内容加载
  await page.waitForSelector('article.Box-row', { timeout: 15000 });
  
  const repos = await page.evaluate(() => {
    const items = document.querySelectorAll('article.Box-row');
    return Array.from(items).map(item => {
      const nameEl = item.querySelector('h2 a');
      const descEl = item.querySelector('p');
      const starsEl = item.querySelector('a[href*="stargazers"]');
      const todayEl = item.querySelector('span.d-inline-block.float-sm-right'); // Today's stars
      
      let name = nameEl ? nameEl.textContent.trim() : '';
      name = name.replace(/\s+/g, '/').replace(/\/+/g, '/');
      
      let todayStars = '';
      if (todayEl) {
        const todayText = todayEl.textContent.trim();
        const match = todayText.match(/(\d+(?:,\d+)*)\s*stars?\s*today/);
        if (match) todayStars = match[1];
      }
      
      return {
        name,
        url: nameEl ? nameEl.href : '',
        desc: descEl ? descEl.textContent.trim() : '',
        stars: starsEl ? starsEl.textContent.trim() : '',
        starsToday: todayStars,
        fetchedAt: new Date().toISOString()
      };
    });
  });
  
  await browser.close();
  return repos;
}

const fs = require('fs');
const path = require('path');

(async () => {
  try {
    let repos = await scrapeGitHubTrending();
    
    // Keep original order from GitHub
    
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const today = `${year}-${month}-${day}`;
    const outputFile = path.join(__dirname, '../data', `${today}.json`);
    
    fs.writeFileSync(outputFile, JSON.stringify(repos, null, 2));
    
    // 更新 latest.json
    const latestFile = path.join(__dirname, '../data/latest.json');
    fs.writeFileSync(latestFile, JSON.stringify(repos, null, 2));
    
    console.log(`\n🔥 抓取到 ${repos.length} 个项目`);
    console.log(`💾 数据已保存: ${outputFile}`);
    
    console.log('\n📄 JSON 输出:');
    console.log(JSON.stringify(repos.slice(0, 10), null, 2));
    
    process.exit(0);
  } catch (error) {
    console.error('❌ 抓取失败:', error.message);
    process.exit(1);
  }
})();
