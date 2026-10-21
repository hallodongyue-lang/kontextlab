-- Editorial enrichment based on explicit fictional contexts. Missing dimensions remain unknown.
update public.kl_samples set research_meta=research_meta||'{"relation":"friends","scene":"social","source":"editorial-1.0"}'::jsonb where seed_code in ('DE001','DE004','DE007','DE009');
update public.kl_samples set research_meta=research_meta||'{"scene":"work","source":"editorial-1.0"}'::jsonb where seed_code in ('DE010','DE012');
update public.kl_samples set research_meta=research_meta||'{"scene":"public","source":"editorial-1.0"}'::jsonb where seed_code in ('DE002','DE005','DE008','DE014','DE025','DE026','DE028','DE029','DE032','DE034');
update public.kl_samples set research_meta=research_meta||'{"phenomenon":"irony","source":"editorial-1.0"}'::jsonb where seed_code in ('DE009','DE010','DE011','DE012','DE013','DE014','DE015');
update public.kl_samples set research_meta=research_meta||'{"phenomenon":"metaphor","scene":"social","source":"editorial-1.0"}'::jsonb where seed_code='DE016';
update public.kl_samples set research_meta=research_meta||'{"phenomenon":"quotation","source":"editorial-1.0"}'::jsonb where seed_code in ('DE037','DE038');
