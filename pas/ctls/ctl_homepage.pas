unit ctl_homepage;
interface
uses
	c_webmodel,
	c_manga,
	c_jenres,
	strings,
	c_http;

type
	IHomepage = interface(IPlugin)
		['{620C53AA-0D41-4FBC-8395-4F8424E893AC}']
	end;
	THomepage = class(TClousureCtl, IHomepage)
	private
		procedure   serveFilters(Proc: PReqProcessor);
		procedure   serveImport(Proc: PReqProcessor);
		procedure   serveDelete(R: TStrings; Proc: PReqProcessor);
		procedure   serveProgress(Proc: PReqProcessor);
		procedure   serveTitle(Proc: PReqProcessor);
		procedure   serveDescr(Proc: PReqProcessor);
		procedure   servePreview(R: TStrings; Proc: PReqProcessor);
		procedure   serveFolder(R: TStrings; Proc: PReqProcessor);
	public
		function    ctlToID(Action: AnsiString): Integer; override;
		procedure   serveAction(ID: Integer; r: TStrings; Proc: PReqProcessor); override;
		function    Name: PAnsiChar; override;
	end;

implementation
uses
	WinAPI
	, WinGDI
	, functions
	, c_buffers
	, opts
	, file_sys
	, c_interactive_lists
	, sql_dbcommon
	, sql_constants
	, graphics
	, graphicex;

function THomepage.ctlToID(Action: AnsiString): Integer;
begin
	result := stringcase(@Action[1], [
		'index'
	, 'filters'
	, 'add'
	, 'delete'
	, 'progress'
	, 'title'
	, 'descr'
	, 'preview'
	, 'folder'
	]);
end;

function THomepage.Name: PAnsiChar;
begin
	result := 'manga';
end;

const
	TA_STR: PAnsiChar = '(<span class="new">+%d</span>) ';
	c_r: array [boolean] of ansistring = ('', 'read');
	com: array [boolean] of ansistring = ('<span class="ongoing">�������</span>', '<span class="complete">���������</span>');
	red: array [boolean] of ansistring = (', <span class="inprocess">� ��������</span>', ', <span class="readed">���������</span>');
	sup: array [boolean] of ansistring = ('', ', <span class="suspended">��������������</span>');
	con: array [boolean] of cardinal   = ($FF0000, $309030);
	coc: array [boolean] of cardinal   = ($008000, $000090);

procedure THomepage.serveAction(ID: Integer; r: TStrings; Proc: PReqProcessor);
var
	u, e, l: AnsiString;
	m: PILItem;
	procedure append(M: PManga);
	var
		t, s, s2, o, c: AnsiString;
	begin
		s2 := '';
		case Length(m.mTitles) of
			0: s := 'TITLE IS MISSING';
			1: s := m.mTitles[0]
		else
			s  := m.mTitles[0];
			s2 := m.mTitles[1];
		end;

		if m.mArchives > 0 then t := Format(TA_STR, [m.mArchives, m.mArchTotal]) else t := '';

		o := ftsi(m.pChapter, 0, 1) + ' / ' + ftsi(m.rChapter, 0, 1);

		if (m.mChaps <= 0) or (m.mChaps = trunc(m.rChapter + 0.01)) then
			c := ''
		else
			c := Format(' (%d)', [m.mChaps]);

		Proc.KeyData.Add('id', its(m.mID));
		Proc.KeyData.Add('id:wide', its(m.mID, 0, 6));
		Proc.KeyData.Add('progress', o);
		Proc.KeyData.Add('chapters', c);
		Proc.KeyData.Add('canread', c_r[m.pChapter < m.rChapter]);
		Proc.KeyData.Add('arch:new', t);
		Proc.KeyData.Add('arch:total', its(m.mArchTotal) + aaxx(m.mArchTotal, ' �����', ['', '�', '��']));
		Proc.KeyData.Add('folder', m.mLink);
		Proc.KeyData.Add('m.title', s);
		Proc.KeyData.Add('m.title2', s2);
		Proc.KeyData.Add('state', com[m.mComplete] + red[m.rReaded] + sup[m.rSuspended]);
		u := join(#13#10, [u, Proc.Process(e)]);
	end;
var
	ml: PIList;
begin
	_cb_new(Proc.IOBuffer, 0);
	try
		case ID of
			0: begin
				Server.LoadMangaList;
				ProcessTemplate(AcceptInclude('plates.tpl'), e);
				ml := Server.GetList;
				if _il_armor(ml) then
					try
						u := '';
						l := '';
						m := ml.Head;
						while m <> nil do begin
							if PManga(m.Data).Filtered then
								append(PManga(m.Data));
							m := m.Prev;
						end;
					finally
						_il_release(ml);
					end
				else
					u := 'Can''t armor dynamic list %)';
				_cb_append(Proc.IOBuffer, '<div class="block">' + u + '</div>');
			end;
			1: serveFilters(Proc);
			2: serveImport(Proc);
			3: serveDelete(r, Proc);
			4: serveProgress(Proc);
			5: serveTitle(Proc);
			6: serveDescr(Proc);
			7: servePreview(r, Proc);
			8: serveFolder(r, Proc);
		end;
	finally
		_cb_end(Proc.IOBuffer);
	end;
end;

procedure THomepage.serveFilters(Proc: PReqProcessor);
const
	chckd: array[boolean] of pansichar = ('', 'checked ');
var
	r, e, f: AnsiString;
	i, n, k: Integer;
	b: Byte;
	Jenres : TJenres;
	procedure appendChB(J: PJenreDesc; Yes, No: Boolean);
	var
		Name: AnsiString;
	begin
		if J <> nil then
			Name := J.Jenre + ' <span class="count">(<font>' + its(J.Mangas) + '</font>)</span>';

		Proc.KeyData.Add('id', its(i));
		Proc.KeyData.Add('id:wide', ITS(i, 0, 2));
		Proc.KeyData.Add('jenre.title', Name);
		Proc.KeyData.Add('chk.yes', chckd[Yes]);
		Proc.KeyData.Add('chk.no', chckd[No]);
		Proc.KeyData.Add('chk.none', chckd[not (Yes or No)]);
		Proc.KeyData.Add('description', J.Descr);

		r := join(#13#10, [r, Proc.Process(f)]);
	end;
	procedure parseParam(p: Integer; out idx: Integer; out val: AnsiString);
	begin
		val := Proc.ParamList.header[p].Name;
		idx := pos('[',val);
		idx := sti(copy(val, idx + 1, pos(']', val) - idx));
		val := Proc.ParamList.header[p].Value;
	end;
var
	o_not, o_yes: TJenreFilter;
	j_not, j_yes: TJenreFilter;
begin
	Server.getFilters(j_yes, j_not);
	if Proc.ParamList['action'] = 'set' then begin
		o_yes := j_yes;
		o_not := j_not;
		j_yes := [];
		j_not := [];
		for i := 0 to Proc.ParamList.Count - 1 do
			if pos('filter', Proc.ParamList.Header[i].Name) > 0 then begin
				parseParam(i, n, e);
				case stringcase(@e[1], ['none', 'yes', 'no']) of
					0: ;
					1: include(j_yes, n);
					2: include(j_not, n);
				end;
			end;

		if (j_not <> o_not) or (j_yes <> o_yes) then begin
			Server.SQL(Format('delete from `%s`', [TBL_NAMES[TBL_FILTER]]));
			e := '';
			for b := 1 to 255 do
				if b in j_not then e := join(';', [e, format(SQL_INSERT_II, [TBL_NAMES[TBL_FILTER], b, 0])]);
			for b := 1 to 255 do
				if b in j_yes then e := join(';', [e, format(SQL_INSERT_II, [TBL_NAMES[TBL_FILTER], b, 1])]);

			if e <> '' then Server.SQL(e);
			Server.LoadMangaList;
		end;
		Server.setFilters(j_yes, j_not);
	end;

	Server.getJenres(Jenres);
	n := Jenres.Count;
	r := '';
	i := 0;
	k := 0;
	ProcessTemplate(AcceptInclude('jfilter.tpl'), f);
	while k < n do begin
		inc(i);
		if not Jenres.Data[i].Valid then continue;
		inc(k);

		appendChB(@Jenres.Data[i], i in j_yes, i in j_not);
	end;
	Proc.KeyData.Add('jenres', '<div class="block">' + r + '</div>');

	_cb_outtemlate(Proc.IOBuffer, 'filters');
end;

procedure THomepage.serveImport(Proc: PReqProcessor);
var
	f: EDBFetch;
	i, id: Integer;
	s, d, u: AnsiString;
	t: TStrings;
begin
	t := nil;
	Proc.KeyData.Delete(['error']);
	if Proc.ParamList['action'] = 'add' then
		repeat
			s := RecodeHTMLTags(Trim(Proc.ParamList['title']));
			d := RecodeHTMLTags(Trim(Proc.ParamList['descr']));
			if s = '' then begin
				Proc.KeyData.Add('error', '* Title can''t be empty');
				break;
			end;

			id := 0;
			t := Explode(#10, s);
			for i := 0 to Length(t) - 1 do
				if fetch3(@f, 'select from `manga` m, `titles` t where (t.`title` = "%s") and (t.`manga` = m.`id`)', [trim(t[i])], ['m.id']) > 0 then begin
					id := STI(f.Rows[0, 0]);
					break;
				end;

			if id = 0 then begin
				if fetch3(@f, 'select from `manga` m', [], ['m.id']) > 0 then begin
					for i := 0 to f.Count - 1 do
						id := imax(id, STI(f.Rows[i, 0]));
				end;
				inc(id);
			end;

			u :=
				Format(SQL_DELETEID   , ['manga', id]) + ';'
			+ Format(SQL_DELETEMANGA, ['links', id]) + ';'
			+ Format(SQL_DELETEMANGA, ['titles', id]) + ';'
			+ Format(SQL_DELETEMANGA, ['m_jenres', id]) + ';'
			+ Format(SQL_DELETEMANGA, ['descrs', id]) + ';'
			+ Format('insert into `%s` values (%d, %d, 1)', [TBL_NAMES[TBL_MANGA], id, 0]) + ';'
			+ Format('insert into `%s` values (%d, 0, 0)', [TBL_NAMES[TBL_STATES], id]) + ';'
			;
			Server.SQL(u);

			u := s;
			for i := 0 to Length(t) - 1 do begin
				if not isCyrylic(t[i])  then u := trim(t[i]);
				Server.SQL(Format(SQL_INSERT_IS, [TBL_NAMES[TBL_TITLES], id, trim(t[i])]));
			end;

			s :=
				Format(SQL_INSERT_IS, [TBL_NAMES[TBL_LINKS], id, LowerCase(makepath(u))]) + ';'
			+ Format(SQL_INSERT_IS, [TBL_NAMES[TBL_DESCRS], id, d]) + ';'
			+ Format(SQL_INSERT_II, [TBL_NAMES[TBL_MHIST], id, UTCSecconds]) + ';'
			;

			Server.SQL(s);
			Server.ListModified;
			Server.LoadMangaList;
			Proc.Redirect('/reader/' + its(id));
		until true;

	_cb_outtemlate(Proc.IOBuffer, 'import');
end;

procedure THomepage.serveProgress(Proc: PReqProcessor);
var
	mId: Integer;
	a: PManga;
	t: AnsiString;
begin
	Proc.Formatter := _JSON_Formatter;

	mid := STI(Proc.ParamList['manga']);
	if mid <= 0 then
		raise Exception.Create('Manga ID not specified!');

	a := _manga_pick(Server.GetList, mid);
	if a <> nil then begin
//		AquireProgress(a);
		Proc.KeyData.Add('rchap', fts(a.rChapter,0,1));
		Proc.KeyData.Add('rtotal', its(a.mChaps));
		Proc.KeyData.Add('archttl', its(a.mArchTotal) + aaxx(a.mArchTotal, ' �����', ['', '�', '��']));
		if a.mArchives > 0 then
			t := Format(TA_STR, [a.mArchives])
		else
			t := '';
		Proc.KeyData.Add('archnew', strsafe(t));
		Proc.KeyData.Add('state', strsafe(com[a.mComplete] + ', ' + red[a.rReaded]));
		Proc.KeyData.Add('descr', strsafe(a.mDescr));
		Proc.KeyData.Add('jenres', join('", "', a.mJenres));

		_cb_outtemlate(Proc.IOBuffer, 'progress');
	end else
		raise Exception.Create('Can''t lock manga list or unknown manga ID#%d', [mid]);
end;

procedure THomepage.serveTitle(Proc: PReqProcessor);
var
	mId: Integer;
	a: PManga;
	s: AnsiString;
	i: Integer;
begin
	Proc.Formatter := _JSON_Formatter;

	mid := STI(Proc.ParamList['manga']);
	if mid <= 0 then
		raise Exception.Create('Manga ID not specified!');

	a := _manga_pick(Server.GetList, mid);
	if a <> nil then begin
		s := Proc.ParamList['title'];
		for i := 0 to length(a.mTitles) - 1 do
			if lstrcmpi(@a.mTitles[i, 1], @s[1]) = 0 then begin
				if Proc.ParamList['param'] = 'delete' then begin
					Server.SQL(Format('delete from `%s` t where t.title = "%s"', [TBL_NAMES[TBL_TITLES], strsafe(a.mTitles[i])]));
					a.mTitles[i] := '';
					a.mTitles := Explode('-:-', join('-:-', a.mTitles));
				end else
					raise Exception.Create('Manga already has this title');
				break;
			end;

		if Proc.ParamList['param'] = 'add' then begin
			Server.SQL(Format(SQL_INSERT_IS, [TBL_NAMES[TBL_TITLES], mid, strsafe(s)]));
			array_push(a.mTitles, s);
		end;

		_cb_append(Proc.IOBuffer, '{"titles": ["' + join('","', a.mTitles) + '"]}');
	end else
		raise Exception.Create('Can''t lock manga list or unknown manga ID#%d', [mid]);
end;

procedure THomepage.serveDescr(Proc: PReqProcessor);
var
	mId: Integer;
	a: PManga;
	s: AnsiString;
begin
//	Proc.Formatter := JSON_Formatter;

	mid := STI(Proc.ParamList['manga']);
	if mid <= 0 then
		raise Exception.Create('Manga ID not specified!');

	a := _manga_pick(Server.GetList, mid);
	if a <> nil then begin
		s := strsafe(join('<br />', explode(#13#10, Proc.ParamList['descr'])));
		Server.SQL(Format('delete from `%s` t where (t.manga = %d)', [TBL_NAMES[TBL_DESCRS], mid]));

		Server.SQL(Format(SQL_INSERT_IS, [TBL_NAMES[TBL_DESCRS], mid, s]));

		Proc.Redirect('/reader/' + its(mid));
	end else
		raise Exception.Create('Can''t lock manga list or unknown manga ID#%d', [mid]);
end;

procedure THomepage.serveDelete(R: TStrings; Proc: PReqProcessor);
var
	id: Integer;
begin
	id := STI(array_shift(r));
	if id = 0 then
		raise Exception.Create('ID not specified!');

	Server.SQL(
		Format(SQL_DELETEID   , ['manga', id]) + ';'
	+ Format(SQL_DELETEMANGA, ['links', id]) + ';'
	+ Format(SQL_DELETEMANGA, ['titles', id]) + ';'
	+ Format(SQL_DELETEMANGA, ['m_jenres', id]) + ';'
	+ Format(SQL_DELETEMANGA, ['descrs', id])
	);

	Server.ListModified;
	Proc.Redirect('/manga');
end;

procedure THomepage.servePreview(R: TStrings; Proc: PReqProcessor);
var
	dw, dh, dx, dy: Integer;
	rw, rh, id: Integer;
	s1, s2: Single;
	origin, preview: AnsiString;

	b: TGraphicExGraphic;
	Y: TGraphic absolute b;
	T: TGraphicClass;
	C: TGraphicExGraphicClass;
	m, g: TBitmap;
begin
	id := STI(array_shift(r));
	if id = 0 then
		raise Exception.Create('Manga ID not specified!');
	Proc.KeyData.Add('id', its(id));

	if Proc.ParamList['action'] = 'generate' then begin
		origin := Trim(Proc.ParamList['origin']);
		rw := sti(Proc.ParamList['rw']);
		rh := sti(Proc.ParamList['rh']);
		dw := sti(Proc.ParamList['dw']);
		dh := sti(Proc.ParamList['dh']);
		dx := sti(Proc.ParamList['dx']);
		dy := sti(Proc.ParamList['dy']);

		Proc.Formatter := _JSON_Formatter;


		if pos('/storage/', LowerCase(origin)) = 1 then
			delete(origin, 1, 9);

		preview := '/prevtmp/' + its(id, 0, 6) + '.bmp';
		DeleteFile(PChar(OPT_DATADIR + preview));

		m := TBitmap.Create;
		try
			b := nil;
			C := FileFormatList.GraphicFromContent(OPT_MANGADIR + '/' + origin);
			try
				if C = nil then begin
					T := FileFormatList.GraphicFromExtension(ExtractFileExt(origin));
					if T = nil then exit;
					Y := T.Create;
					Y.LoadFromFile(OPT_MANGADIR + '/' + origin);
				end else begin
					b := C.Create;
					b.LoadFromFile(OPT_MANGADIR + '/' + origin);
				end;
				m.Assign(b);
			finally
				if b <> nil then b.Free;
			end;
			g := TBitmap.Create;
			try
				g.Assign(m);
				s1 := g.Width / rw;
				s2 := g.Height / rh;
				dx := round(dx * s1);
				dy := round(dy * s2);
				rw := round(dw * s1);
				rh := round(dh * s2);

				m.Width := rw;
				m.Height := rh;
				PatBlt(m.Canvas.Handle, 0, 0, rw, rh, PATCOPY);
				BitBlt(
					m.Canvas.Handle,
					0, 0, rw, rh,
					g.Canvas.Handle,
					dx, dy,
					SRCCopy
				);
			finally
				g.Free;
			end;

			Stretch(63, 96, sfBox, 0, m);
			m.SaveToFile(OPT_DATADIR + preview);
		except
			m.Free;
		end;

		Proc.Redirect(escapeslashes(strsafe('/data' + preview)));
		exit;
	end;
	if Proc.ParamList['action'] = 'save' then begin
		origin := ITS(id, 0, 6) + '.bmp';
		DeleteFile(pchar(OPT_DATADIR + '/previews/' + origin));
		MoveFile(PChar(OPT_DATADIR + '/prevtmp/' + origin), PChar(OPT_DATADIR + '/previews/' + origin));
		Proc.Redirect('/reader/' + its(id));
		exit;
	end;
	_cb_outtemlate(Proc.IOBuffer, 'preview');
end;

procedure THomepage.serveFolder(R: TStrings; Proc: PReqProcessor);
var
	mId: Integer;
	a: PManga;
	old, new, p: AnsiString;
begin
	mid := STI(Proc.ParamList['manga']);
	if mid <= 0 then
		raise Exception.Create('Manga ID not specified!');

	a := _manga_pick(Server.GetList, mid);
	if a <> nil then begin
		p := LowerCase(makepath(Proc.ParamList['folder']));
		if p <> a.mLink then begin
			Server.SQL(Format(SQL_DELETEMANGA, [TBL_NAMES[TBL_LINKS], mid]));
			Server.SQL(Format(SQL_INSERT_IS, [TBL_NAMES[TBL_LINKS], mid, p]));

			old := Format('%s\\%s', [OPT_MANGADIR, a.mLink]);
			new := Format('%s\\%s', [OPT_MANGADIR, p]);
			if FileExists(old) then
				MoveFile(PAnsiChar(old), PAnsiChar(new));

			a.mLink := p;
		end;

		Proc.Redirect('/reader/' + its(mid));
	end else
		raise Exception.Create('Can''t lock manga list or unknown manga ID#%d', [mid]);
end;

end.
