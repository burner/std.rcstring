all:
	dmd -unittest -debug -main -profile=gc -w -g -cov rcstring.d
