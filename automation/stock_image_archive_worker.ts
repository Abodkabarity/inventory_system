import {db,tick} from '../supabase/functions/stock-image-archive/index.ts';
// Local source access, durable cloud queue/storage/progress. The monitor never
// sees the service key. The computer must remain awake for ingestion to proceed.
while(true){
  try{
    const [job]=await db('stock_image_archive_jobs?id=eq.catalog-v1&select=status');
    if(job?.status==='complete'){console.log(new Date().toISOString(),'Archive complete');break;}
    if(job?.status==='paused'){await new Promise(r=>setTimeout(r,10000));continue;}
    const result=await tick();console.log(new Date().toISOString(),JSON.stringify(result));
  }catch(e){console.error(new Date().toISOString(),String(e).slice(0,400));}
  await new Promise(r=>setTimeout(r,5000));
}
